package bushscript;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Bushscript
 *
 * A one-file local browser launcher with a loopback-only HTTP/HTTPS forward
 * proxy. It uses an installed Chromium browser for rendering. HTTPS traffic is
 * tunneled with CONNECT and is not decrypted.
 *
 * Compile: javac Bushscript.java
 * Run:     java Bushscript
 * URL:     java Bushscript https://example.com
 * Options: java Bushscript --port=8899 --browser="C:\path\chrome.exe"
 */

public final class Bushscript {
    private static final int DEFAULT_PORT = 8899;
    private static final int MAX_HEADER_BYTES = 64 * 1024;
    private static final int CONNECT_TIMEOUT_MS = 15_000;
    private static final AtomicLong CONNECTIONS = new AtomicLong();

    private final ExecutorService workers = Executors.newCachedThreadPool(r -> {
        Thread thread = new Thread(r, "Bush-proxy-worker");
        thread.setDaemon(true);
        return thread;
    });

    private final ServerSocket server;

    private Bushscript(int port) throws IOException {
        server = new ServerSocket();
        server.setReuseAddress(true);
        server.bind(new InetSocketAddress("127.0.0.1", port));
    }

    public static void main(String[] args) throws Exception {
        if (Arrays.asList(args).contains("--help")) {
            printHelp();
            return;
        }

        int port = DEFAULT_PORT;
        String requestedBrowser = null;
        String startUrl = "https://google.com";
        boolean noLaunch = false;

        for (String arg : args) {
            if (arg.startsWith("--port=")) {
                port = Integer.parseInt(arg.substring("--port=".length()));
            } else if (arg.startsWith("--browser=")) {
                requestedBrowser = unquote(arg.substring("--browser=".length()));
            } else if (arg.equals("--no-launch")) {
                noLaunch = true;
            } else if (!arg.startsWith("--")) {
                startUrl = normalizeUrl(arg);
            }
        }

        Bushscript proxy = new Bushscript(port);
        int actualPort = proxy.server.getLocalPort();
        Runtime.getRuntime().addShutdownHook(new Thread(proxy::close, "Bush-shutdown"));
        proxy.start();

        System.out.println("Bush Local Browser");
        System.out.println("Proxy:   http://127.0.0.1:" + actualPort);
        System.out.println("Privacy: HTTPS is tunneled without decryption");

        if (!noLaunch) {
            Path browser = findBrowser(requestedBrowser);
            Process browserProcess = launchBrowser(browser, actualPort, startUrl);
            System.out.println("Browser: " + browser);
            System.out.println("The proxy will automatically stop when you close the browser...");
            
            // Block the main thread until the browser process ends
            browserProcess.waitFor();
            System.out.println("Browser closed. Shutting down.");
        } else {
            System.out.println("Browser launch disabled; press Ctrl+C to stop.");
            // Only wait indefinitely if we didn't launch the browser
            new CountDownLatch(1).await();
        }
    }

    private void start() {
        Thread acceptor = new Thread(() -> {
            while (!server.isClosed()) {
                try {
                    Socket client = server.accept();
                    client.setTcpNoDelay(true);
                    workers.execute(() -> handle(client));
                } catch (IOException error) {
                    if (!server.isClosed()) {
                        System.err.println("Proxy accept error: " + error.getMessage());
                    }
                }
            }
        }, "Bush-proxy-acceptor");
        acceptor.setDaemon(true);
        acceptor.start();
    }

    private void handle(Socket client) {
        long id = CONNECTIONS.incrementAndGet();
        try (client) {
            client.setSoTimeout(30_000);
            InputStream clientIn = client.getInputStream();
            OutputStream clientOut = client.getOutputStream();
            byte[] headerBytes = readHeader(clientIn);
            if (headerBytes.length == 0) {
                return;
            }

            String header = new String(headerBytes, StandardCharsets.ISO_8859_1);
            String[] lines = header.split("\\r?\\n");
            String[] request = lines[0].split(" ", 3);
            if (request.length < 2) {
                sendError(clientOut, 400, "Bad Request");
                return;
            }

            String method = request[0].toUpperCase(Locale.ROOT);
            if ("CONNECT".equals(method)) {
                Target target = parseAuthority(request[1], 443);
                System.out.printf("[%d] CONNECT %s:%d%n", id, target.host, target.port);
                tunnelConnect(clientIn, clientOut, target);
                return;
            }

            Target target = targetForHttp(request[1], lines);
            System.out.printf("[%d] %s %s:%d%n", id, method, target.host, target.port);
            forwardHttp(clientIn, clientOut, header, request, target);
        } catch (Exception error) {
            System.err.printf("[%d] %s%n", id, error.getMessage());
        }
    }

    private void tunnelConnect(InputStream clientIn, OutputStream clientOut, Target target)
            throws IOException {
        try (Socket upstream = connect(target)) {
            clientOut.write(("HTTP/1.1 200 Connection Established\r\n"
                    + "Proxy-Agent: BushLocal/1.0\r\n\r\n")
                    .getBytes(StandardCharsets.ISO_8859_1));
            clientOut.flush();
            relayBothWays(clientIn, clientOut, upstream);
        } catch (IOException error) {
            sendError(clientOut, 502, "Unable to connect");
            throw error;
        }
    }

    private void forwardHttp(
            InputStream clientIn,
            OutputStream clientOut,
            String originalHeader,
            String[] request,
            Target target) throws IOException {
        try (Socket upstream = connect(target)) {
            OutputStream upstreamOut = upstream.getOutputStream();
            String rewritten = rewriteHttpHeader(originalHeader, request);
            upstreamOut.write(rewritten.getBytes(StandardCharsets.ISO_8859_1));
            upstreamOut.flush();
            relayBothWays(clientIn, clientOut, upstream);
        } catch (IOException error) {
            sendError(clientOut, 502, "Unable to connect");
            throw error;
        }
    }

    private void relayBothWays(InputStream clientIn, OutputStream clientOut, Socket upstream)
            throws IOException {
        upstream.setTcpNoDelay(true);
        upstream.setSoTimeout(0);
        InputStream upstreamIn = upstream.getInputStream();
        OutputStream upstreamOut = upstream.getOutputStream();

        workers.execute(() -> copyAndHalfClose(clientIn, upstreamOut, upstream));
        copyAndHalfClose(upstreamIn, clientOut, null);
    }

    private static void copyAndHalfClose(InputStream in, OutputStream out, Socket outputSocket) {
        byte[] buffer = new byte[32 * 1024];
        try {
            int count;
            while ((count = in.read(buffer)) >= 0) {
                out.write(buffer, 0, count);
                out.flush();
            }
        } catch (IOException ignored) {
            // Closing either side of a tunnel normally interrupts the other copy.
        } finally {
            if (outputSocket != null) {
                try {
                    outputSocket.shutdownOutput();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static Socket connect(Target target) throws IOException {
        Socket socket = new Socket();
        socket.connect(new InetSocketAddress(target.host, target.port), CONNECT_TIMEOUT_MS);
        return socket;
    }

    private static byte[] readHeader(InputStream input) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        int state = 0;
        while (bytes.size() < MAX_HEADER_BYTES) {
            int value = input.read();
            if (value < 0) {
                break;
            }
            bytes.write(value);
            state = switch (state) {
                case 0 -> value == '\r' ? 1 : 0;
                case 1 -> value == '\n' ? 2 : 0;
                case 2 -> value == '\r' ? 3 : 0;
                case 3 -> value == '\n' ? 4 : 0;
                default -> 4;
            };
            if (state == 4) {
                return bytes.toByteArray();
            }
        }
        if (bytes.size() >= MAX_HEADER_BYTES) {
            throw new IOException("Request headers are too large");
        }
        return bytes.toByteArray();
    }

    private static Target targetForHttp(String requestTarget, String[] lines)
            throws IOException {
        try {
            URI uri = new URI(requestTarget);
            if (uri.getHost() != null) {
                int port = uri.getPort() > 0 ? uri.getPort() : 80;
                return new Target(uri.getHost(), port);
            }
        } catch (URISyntaxException ignored) {
        }

        for (String line : lines) {
            if (line.regionMatches(true, 0, "Host:", 0, 5)) {
                return parseAuthority(line.substring(5).trim(), 80);
            }
        }
        throw new IOException("HTTP request has no destination host");
    }

    private static String rewriteHttpHeader(String header, String[] request) {
        String target = request[1];
        try {
            URI uri = new URI(target);
            if (uri.isAbsolute()) {
                String path = uri.getRawPath();
                if (path == null || path.isEmpty()) {
                    path = "/";
                }
                if (uri.getRawQuery() != null) {
                    path += "?" + uri.getRawQuery();
                }
                target = path;
            }
        } catch (URISyntaxException ignored) {
        }

        StringBuilder result = new StringBuilder();
        result.append(request[0]).append(' ').append(target);
        if (request.length == 3) {
            result.append(' ').append(request[2]);
        }
        result.append("\r\n");

        String[] lines = header.split("\\r?\\n");
        for (int index = 1; index < lines.length; index++) {
            String line = lines[index];
            if (line.isEmpty()) {
                continue;
            }
            if (!line.regionMatches(true, 0, "Proxy-Connection:", 0, 17)
                    && !line.regionMatches(true, 0, "Proxy-Authorization:", 0, 20)) {
                result.append(line).append("\r\n");
            }
        }
        result.append("\r\n");
        return result.toString();
    }

    private static Target parseAuthority(String authority, int defaultPort)
            throws IOException {
        String value = authority.trim();
        if (value.startsWith("[")) {
            int end = value.indexOf(']');
            if (end < 0) {
                throw new IOException("Invalid IPv6 destination");
            }
            String host = value.substring(1, end);
            int port = end + 1 < value.length() && value.charAt(end + 1) == ':'
                    ? parsePort(value.substring(end + 2))
                    : defaultPort;
            return new Target(host, port);
        }

        int colon = value.lastIndexOf(':');
        if (colon > 0 && value.indexOf(':') == colon) {
            return new Target(value.substring(0, colon), parsePort(value.substring(colon + 1)));
        }
        if (value.isBlank()) {
            throw new IOException("Empty destination");
        }
        return new Target(value, defaultPort);
    }

    private static int parsePort(String value) throws IOException {
        try {
            int port = Integer.parseInt(value);
            if (port < 1 || port > 65_535) {
                throw new NumberFormatException();
            }
            return port;
        } catch (NumberFormatException error) {
            throw new IOException("Invalid destination port");
        }
    }

    private static void sendError(OutputStream output, int status, String message) {
        try {
            String body = "Bush Proxy: " + message + "\n";
            String response = "HTTP/1.1 " + status + " " + message + "\r\n"
                    + "Content-Type: text/plain; charset=utf-8\r\n"
                    + "Content-Length: " + body.getBytes(StandardCharsets.UTF_8).length + "\r\n"
                    + "Connection: close\r\n\r\n"
                    + body;
            output.write(response.getBytes(StandardCharsets.UTF_8));
            output.flush();
        } catch (IOException ignored) {
        }
    }

    private static Path findBrowser(String requested) throws IOException {
        if (requested != null) {
            Path path = Path.of(requested);
            if (Files.isRegularFile(path)) {
                return path;
            }
            throw new IOException("Browser executable not found: " + requested);
        }

        List<Path> candidates = new ArrayList<>();
        addCandidate(candidates, System.getenv("LOCALAPPDATA"),
                "Google", "Chrome", "Application", "chrome.exe");
        addCandidate(candidates, System.getenv("PROGRAMFILES"),
                "Google", "Chrome", "Application", "chrome.exe");
        addCandidate(candidates, System.getenv("PROGRAMFILES(X86)"),
                "Google", "Chrome", "Application", "chrome.exe");
        addCandidate(candidates, System.getenv("PROGRAMFILES(X86)"),
                "Microsoft", "Edge", "Application", "msedge.exe");
        addCandidate(candidates, System.getenv("PROGRAMFILES"),
                "Microsoft", "Edge", "Application", "msedge.exe");

        return candidates.stream()
                .filter(Files::isRegularFile)
                .findFirst()
                .orElseThrow(() -> new IOException(
                        "Chrome or Edge was not found. Use --browser=\"C:\\path\\browser.exe\""));
    }

    private static void addCandidate(List<Path> candidates, String root, String... parts) {
        if (root == null || root.isBlank()) {
            return;
        }
        Path path = Path.of(root);
        for (String part : parts) {
            path = path.resolve(part);
        }
        candidates.add(path);
    }

    // Modification: We now return the Process object created by the ProcessBuilder
    private static Process launchBrowser(Path browser, int port, String url) throws IOException {
        Path profile = Path.of(System.getProperty("user.home"), ".Bush-local-browser");
        Files.createDirectories(profile);
        return new ProcessBuilder(
                browser.toString(),
                "--user-data-dir=" + profile,
                "--proxy-server=http://127.0.0.1:" + port,
                "--proxy-bypass-list=<-loopback>",
                "--no-first-run",
                "--no-default-browser-check",
                "--new-window",
                url)
                .inheritIO()
                .start();
    }

    private static String normalizeUrl(String value) {
        String trimmed = unquote(value.trim());
        if (trimmed.matches("^[A-Za-z][A-Za-z0-9+.-]*://.*$")) {
            return trimmed;
        }
        if (trimmed.contains(".") && !trimmed.contains(" ")) {
            return "https://" + trimmed;
        }
        return "https://duckduckgo.com/?q="
                + java.net.URLEncoder.encode(trimmed, StandardCharsets.UTF_8);
    }

    private static String unquote(String value) {
        if (value.length() >= 2
                && ((value.startsWith("\"") && value.endsWith("\""))
                || (value.startsWith("'") && value.endsWith("'")))) {
            return value.substring(1, value.length() - 1);
        }
        return value;
    }

    private void close() {
        try {
            server.close();
        } catch (IOException ignored) {
        }
        workers.shutdownNow();
    }

    private static void printHelp() {
        System.out.println("""
                Bush Local Browser

                Usage:
                  javac Bushscript.java
                  java Bushscript [URL or search] [options]

                Options:
                  --port=NUMBER       Local proxy port (default 8899)
                  --browser=PATH      Chrome/Edge executable
                  --no-launch         Start only the local proxy
                  --help              Show this help

                The proxy listens only on 127.0.0.1. HTTPS uses CONNECT tunneling;
                Bush cannot inspect or modify encrypted page contents.
                """);
    }

    private record Target(String host, int port) {
    }
}
