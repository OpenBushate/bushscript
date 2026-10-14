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
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class Bushscript {
    private static final int DEFAULT_PORT = 8899;
    private static final int MAX_HEADER_BYTES = 64 * 1024;
    private static final int CONNECT_TIMEOUT_MS = 15_000;
    private static final Pattern PAGE_TARGET = Pattern.compile("\"type\"\\s*:\\s*\"page\"");

    // ---- AdBlock state -------------------------------------------------------
    private static final Set<String> BLOCKED_DOMAINS = ConcurrentHashMap.newKeySet();
    private static volatile boolean adblockEnabled = true;

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

        System.out.println("If this program seemingly freezes, navigate to the terminal window "
                + "and click CTRL + C, if this does not work restart the program completely. "
                + "If further issues persist contact bush_support@downingtownstem.org");

        int port = DEFAULT_PORT;
        String requestedBrowser = null;
        String startUrl = "https://google.com";
        boolean noLaunch = false;
        List<Path> extraBlocklists = new ArrayList<>();

        for (String arg : args) {
            if (arg.startsWith("--port=")) {
                port = Integer.parseInt(arg.substring("--port=".length()));
            } else if (arg.startsWith("--browser=")) {
                requestedBrowser = unquote(arg.substring("--browser=".length()));
            } else if (arg.startsWith("--blocklist=")) {
                extraBlocklists.add(Path.of(unquote(arg.substring("--blocklist=".length()))));
            } else if (arg.equals("--no-adblock")) {
                adblockEnabled = false;
            } else if (arg.equals("--no-launch")) {
                noLaunch = true;
            } else if (!arg.startsWith("--")) {
                startUrl = normalizeUrl(arg);
            }
        }

        if (adblockEnabled) {
            loadBuiltInBlocklist();
            // Optional user list that is picked up automatically if present.
            Path userList = Path.of(System.getProperty("user.home"),
                    ".Bush-local-browser", "blocklist.txt");
            if (Files.isRegularFile(userList)) {
                extraBlocklists.add(0, userList);
            }
            for (Path list : extraBlocklists) {
                try {
                    loadBlocklistFile(list);
                } catch (IOException error) {
                    System.err.println("Could not read blocklist " + list + ": " + error.getMessage());
                }
            }
        }

        Bushscript proxy = new Bushscript(port);
        int actualPort = proxy.server.getLocalPort();
        Runtime.getRuntime().addShutdownHook(new Thread(proxy::close, "Bush-shutdown"));
        proxy.start();

        if (!noLaunch) {
            Path browser = findBrowser(requestedBrowser);
            Process browserProcess = launchBrowser(browser, actualPort, startUrl);

            Process polish = startWindowPolish(profileDir());

            // Block until the browser is really closed, then exit immediately. A non-zero
            // exit code makes the launcher .bat pause so the message can be read.
            boolean startedOk = waitForBrowser(browserProcess, profileDir());
            if (polish != null) {
                polish.destroy();
            }
            System.exit(startedOk ? 0 : 1);
        } else {
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
                } catch (IOException ignored) {
                    // Server closed or a transient accept failure; the loop re-checks isClosed().
                }
            }
        }, "Bush-proxy-acceptor");
        acceptor.setDaemon(true);
        acceptor.start();
    }

    private void handle(Socket client) {
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
                if (isBlocked(target.host)) {
                    sendError(clientOut, 403, "Blocked by Bush AdBlock");
                    return;
                }
                tunnelConnect(clientIn, clientOut, target);
                return;
            }

            Target target = targetForHttp(request[1], lines);
            if (isBlocked(target.host)) {
                sendError(clientOut, 403, "Blocked by Bush AdBlock");
                return;
            }
            forwardHttp(clientIn, clientOut, header, request, target);
        } catch (Exception ignored) {
            // Per-connection failures (resets, timeouts, bad requests) are expected; stay quiet.
        }
    }

    // ---- AdBlock -------------------------------------------------------------

    /** True if the host, or any parent domain of it, is on the blocklist. */
    private static boolean isBlocked(String host) {
        if (!adblockEnabled || host == null || host.isEmpty()) {
            return false;
        }
        String current = host.toLowerCase(Locale.ROOT);
        if (current.endsWith(".")) {
            current = current.substring(0, current.length() - 1);
        }
        while (true) {
            if (BLOCKED_DOMAINS.contains(current)) {
                return true;
            }
            int dot = current.indexOf('.');
            if (dot < 0) {
                return false;
            }
            current = current.substring(dot + 1);
        }
    }

    /**
     * Loads a blocklist file. Understands hosts-file format ("0.0.0.0 ads.example.com"),
     * plain domain-per-line lists, and simple Adblock-style "||ads.example.com^" rules.
     * Returns the number of domains added.
     */
    private static int loadBlocklistFile(Path file) throws IOException {
        int before = BLOCKED_DOMAINS.size();
        for (String line : Files.readAllLines(file, StandardCharsets.UTF_8)) {
            String domain = parseBlocklistLine(line);
            if (domain != null) {
                BLOCKED_DOMAINS.add(domain);
            }
        }
        return BLOCKED_DOMAINS.size() - before;
    }

    private static String parseBlocklistLine(String raw) {
        String line = raw;
        int hash = line.indexOf('#');
        if (hash >= 0) {
            line = line.substring(0, hash);
        }
        line = line.trim();
        if (line.isEmpty() || line.startsWith("!") || line.startsWith("[")) {
            return null;
        }

        if (line.startsWith("||")) {
            line = line.substring(2);
            int caret = line.indexOf('^');
            if (caret >= 0) {
                // Skip rules with options such as ^$third-party; keep the plain domain part.
                line = line.substring(0, caret);
            }
        } else {
            String[] parts = line.split("\\s+");
            if (parts.length >= 2
                    && (parts[0].equals("0.0.0.0") || parts[0].equals("127.0.0.1"))) {
                line = parts[1];
            } else if (parts.length == 1) {
                line = parts[0];
            } else {
                return null;
            }
        }

        line = line.toLowerCase(Locale.ROOT);
        while (line.startsWith(".")) {
            line = line.substring(1);
        }
        if (!line.contains(".") || !line.matches("[a-z0-9._-]+")) {
            return null;
        }
        return line;
    }

    private static void loadBuiltInBlocklist() {
        BLOCKED_DOMAINS.addAll(List.of(
                // Google ads / analytics
                "doubleclick.net", "googlesyndication.com", "googleadservices.com",
                "googletagservices.com", "adservice.google.com", "google-analytics.com",
                "2mdn.net", "admob.com", "adsense.com",
                // Major ad exchanges and networks
                "adnxs.com", "adsrvr.org", "advertising.com", "amazon-adsystem.com",
                "criteo.com", "criteo.net", "rubiconproject.com", "pubmatic.com",
                "openx.net", "casalemedia.com", "smartadserver.com", "adform.net",
                "bidswitch.net", "contextweb.com", "sharethrough.com", "teads.tv",
                "media.net", "yieldmo.com", "33across.com", "lijit.com", "sovrn.com",
                "indexww.com", "tapad.com", "gumgum.com", "triplelift.com",
                "connatix.com", "adroll.com", "ad.gt", "mathtag.com", "turn.com",
                "rlcdn.com", "adsymptotic.com", "serving-sys.com", "flashtalking.com",
                "zedo.com", "adcolony.com", "smaato.net", "inmobi.com",
                // Native / recommendation ad widgets
                "taboola.com", "outbrain.com", "revcontent.com", "mgid.com", "zemanta.com",
                // Pop-ups / pop-unders / shady networks
                "popads.net", "popcash.net", "propellerads.com", "exoclick.com",
                "juicyads.com", "trafficjunky.com", "adsterra.com", "clickadu.com",
                "hilltopads.net",
                // Social platform ad endpoints
                "ads-twitter.com", "ads.linkedin.com", "ads.yahoo.com", "analytics.yahoo.com",
                "ads.tiktok.com", "ads.pinterest.com", "ads.reddit.com",
                // Verification / tracking / data brokers
                "moatads.com", "adsafeprotected.com", "doubleverify.com", "scorecardresearch.com",
                "quantserve.com", "quantcount.com", "bluekai.com", "demdex.net", "krxd.net",
                "everesttech.net", "eyeota.net", "lotame.com", "hotjar.com", "mouseflow.com"));
    }

    // ---- Proxy plumbing ------------------------------------------------------

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

    // Returns the Process object created by the ProcessBuilder
    private static Process launchBrowser(Path browser, int port, String url) throws IOException {
        Path profile = profileDir();
        Files.createDirectories(profile);
        return new ProcessBuilder(
                browser.toString(),
                "--user-data-dir=" + profile,
                "--disable-background-mode",
                "--hide-crash-restore-bubble",
                "--remote-debugging-port=0",
                "--proxy-server=http://127.0.0.1:" + port,
                "--proxy-bypass-list=<-loopback>",
                "--no-first-run",
                "--no-default-browser-check",
                "--new-window",
                url)
                .inheritIO()
                .start();
    }

    private static Path profileDir() {
        return Path.of(System.getProperty("user.home"), ".Bush-local-browser");
    }

    /**
     * Keeps the proxy alive until every browser window is closed.
     *
     * Waiting on the launched process is unreliable: Chrome/Edge may hand the window to an
     * already-running instance and exit at once, or stay alive in the background after the last
     * window closes. Instead the browser is started with a local debugging port (listening on
     * 127.0.0.1 only) and we count its open pages. If that port is unavailable we fall back to
     * the launcher process plus the profile's lockfile.
     */
    private static boolean waitForBrowser(Process launcher, Path profile) throws InterruptedException {
        Path portFile = profile.resolve("DevToolsActivePort");
        HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofMillis(400)).build();
        long started = System.nanoTime();
        boolean sawPage = false;
        boolean startedOk = true;
        int closedChecks = 0;
        int idleChecks = 0;

        while (true) {
            int pages = countOpenPages(http, portFile);

            if (pages > 0) {
                sawPage = true;
                closedChecks = 0;
                idleChecks = 0;
            } else if (sawPage) {
                // Zero pages, or the debugging port vanished: the browser has been closed.
                boolean portGone = pages < 0;
                if (portGone && !launcher.isAlive() && !profileLocked(profile)) {
                    break; // the browser process has fully exited, no need to wait further
                }
                if (++closedChecks >= (portGone ? 2 : 4)) {
                    break;
                }
            } else if (!launcher.isAlive() && !profileLocked(profile)) {
                // No debugging info and the browser is not running at all.
                if (++idleChecks >= 20) {
                    long elapsedMs = (System.nanoTime() - started) / 1_000_000;
                    if (elapsedMs < 30_000) {
                        System.err.println("The browser closed right after starting (exit code "
                                + launcher.exitValue() + "). Close any leftover Chrome/Edge "
                                + "windows and try again, or choose a browser with "
                                + "--browser=\"C:\\path\\browser.exe\"");
                        startedOk = false;
                    }
                    break;
                }
            } else {
                idleChecks = 0;
            }
            Thread.sleep(250);
        }

        // Release any background processes still holding the profile.
        launcher.descendants().forEach(ProcessHandle::destroy);
        launcher.destroy();
        return startedOk;
    }

    /** Number of open browser pages/tabs, or -1 if the debugging port can't be reached. */
    private static int countOpenPages(HttpClient http, Path portFile) {
        try {
            int port = Integer.parseInt(Files.readAllLines(portFile).get(0).trim());
            HttpRequest request = HttpRequest
                    .newBuilder(URI.create("http://127.0.0.1:" + port + "/json/list"))
                    .timeout(Duration.ofMillis(1_500))
                    .build();
            String body = http.send(request, HttpResponse.BodyHandlers.ofString()).body();
            int count = 0;
            Matcher matcher = PAGE_TARGET.matcher(body);
            while (matcher.find()) {
                count++;
            }
            return count;
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            return -1;
        } catch (Exception error) {
            return -1;
        }
    }

    /** True while a Chromium browser is running on this profile. */
    private static boolean profileLocked(Path profile) {
        Path lock = profile.resolve("lockfile");
        if (!Files.exists(lock)) {
            return false;
        }
        try (FileChannel ignored = FileChannel.open(lock, StandardOpenOption.WRITE)) {
            return false;
        } catch (IOException error) {
            return true;
        }
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

    /**
     * Windows only. Starts a small hidden PowerShell helper that gives the browser window the
     * BushScript icon and taskbar identity, so it appears as part of BushScript instead of as a
     * separate Chrome/Edge button. Purely cosmetic and best effort: returns null if anything is
     * missing, and the browser then simply keeps its normal icon. Creating a file named
     * nopolish.txt in the BushScript folder turns it off.
     */
    private static Process startWindowPolish(Path profile) {
        try {
            if (!System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
                return null;
            }
            String appDir = System.getenv("APPDIR");
            String launcher = System.getenv("LAUNCHER");
            String windir = System.getenv("WINDIR");
            if (appDir == null || launcher == null || windir == null) {
                return null;
            }
            Path icon = Path.of(appDir, "bush.ico");
            if (!Files.isRegularFile(icon) || Files.exists(Path.of(appDir, "nopolish.txt"))) {
                return null;
            }
            Path script = Path.of(appDir, "bushpolish.ps1");
            Files.writeString(script, POLISH_SCRIPT, StandardCharsets.US_ASCII);
            return new ProcessBuilder(
                    "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-WindowStyle", "Hidden", "-File", script.toString(),
                    "-ProfileDir", profile.toString(),
                    "-IconPath", icon.toString(),
                    "-Conhost", Path.of(windir, "System32", "conhost.exe").toString(),
                    "-Launcher", launcher,
                    "-ParentPid", Long.toString(ProcessHandle.current().pid()))
                    .redirectErrorStream(true)
                    .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                    .start();
        } catch (Exception error) {
            return null;
        }
    }

    private static final String POLISH_SCRIPT = """
param([string]$ProfileDir, [string]$IconPath, [string]$Conhost, [string]$Launcher, [int]$ParentPid)
# BushScript window polish: gives the browser window the BushScript name/icon identity on the taskbar.
# Everything here is best effort; if anything is unavailable the browser simply keeps its normal icon.
$ErrorActionPreference = 'Stop'
try {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class BushWin
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr p;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint c);
        [PreserveSig] int GetAt(uint i, out PROPERTYKEY k);
        [PreserveSig] int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
        [PreserveSig] int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v);
        [PreserveSig] int Commit();
    }

    delegate bool EnumProc(IntPtr h, IntPtr l);

    [DllImport("shell32.dll")]
    static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore ppv);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr pbc, int flags, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore ppv);
    [DllImport("ole32.dll")]
    static extern int PropVariantClear(ref PROPVARIANT pv);
    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumProc proc, IntPtr l);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")]
    static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")]
    static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")]
    static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint flags);

    static readonly Guid IID_PropertyStore = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    static readonly Guid FMTID_AppUserModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    static void SetString(IPropertyStore ps, uint pid, string value)
    {
        PROPERTYKEY key = new PROPERTYKEY();
        key.fmtid = FMTID_AppUserModel;
        key.pid = pid;
        PROPVARIANT pv = new PROPVARIANT();
        pv.vt = 31; // VT_LPWSTR
        pv.p = Marshal.StringToCoTaskMemUni(value);
        try { ps.SetValue(ref key, ref pv); }
        finally { PropVariantClear(ref pv); }
    }

    // Top-level browser windows (class Chrome_WidgetWin_1) that belong to the given process ids.
    public static long[] FindWindows(int[] pids)
    {
        List<long> found = new List<long>();
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            if (!IsWindowVisible(h)) return true;
            if (GetWindow(h, 4) != IntPtr.Zero) return true;   // GW_OWNER: skip owned popups
            if (GetWindowTextLength(h) == 0) return true;
            StringBuilder sb = new StringBuilder(64);
            GetClassName(h, sb, sb.Capacity);
            if (sb.ToString() != "Chrome_WidgetWin_1") return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, (int)pid) >= 0) found.Add(h.ToInt64());
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }

    // Taskbar identity of a window: id + relaunch command/icon/name (lets the user pin it as "BushScript").
    public static void SetWindowIdentity(long hwnd, string appId, string relaunchCommand, string iconResource, string displayName)
    {
        Guid iid = IID_PropertyStore;
        IPropertyStore ps;
        if (SHGetPropertyStoreForWindow(new IntPtr(hwnd), ref iid, out ps) != 0 || ps == null) return;
        try
        {
            SetString(ps, 2, relaunchCommand);
            SetString(ps, 3, iconResource);
            SetString(ps, 4, displayName);
            SetString(ps, 5, appId);
            ps.Commit();
        }
        finally { Marshal.ReleaseComObject(ps); }
    }

    // Same identity on a .lnk so the running window groups under the pinned shortcut.
    public static void SetShortcutIdentity(string lnkPath, string appId)
    {
        Guid iid = IID_PropertyStore;
        IPropertyStore ps;
        if (SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 2, ref iid, out ps) != 0 || ps == null) return;
        try
        {
            SetString(ps, 5, appId);
            ps.Commit();
        }
        finally { Marshal.ReleaseComObject(ps); }
    }

    public static void SetWindowIcons(long hwnd, string icoPath)
    {
        IntPtr big = LoadImage(IntPtr.Zero, icoPath, 1, 48, 48, 0x10);    // IMAGE_ICON, LR_LOADFROMFILE
        IntPtr small = LoadImage(IntPtr.Zero, icoPath, 1, 16, 16, 0x10);
        if (big != IntPtr.Zero) SendMessage(new IntPtr(hwnd), 0x80, new IntPtr(1), big);    // WM_SETICON, ICON_BIG
        if (small != IntPtr.Zero) SendMessage(new IntPtr(hwnd), 0x80, IntPtr.Zero, small);  // ICON_SMALL
    }
}
'@

    $appId = 'BushScript.Browser'
    $q = [string][char]34
    $Relaunch = $q + $Conhost + $q + ' --headless cmd /c ' + $q + $q + $Launcher + $q + $q

    # Give the Desktop / Start menu shortcuts the same identity so the running window joins them.
    foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
        $lnk = Join-Path $dir 'BushScript.lnk'
        if (Test-Path $lnk) { try { [BushWin]::SetShortcutIdentity($lnk, $appId) } catch { } }
    }

    $seen = @{}
    while ($true) {
        if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
        $pids = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProfileDir) } |
            ForEach-Object { [int]$_.ProcessId })
        if ($pids.Count -gt 0) {
            foreach ($h in [BushWin]::FindWindows([int[]]$pids)) {
                if (-not $seen.ContainsKey($h)) {
                    try { [BushWin]::SetWindowIdentity($h, $appId, $Relaunch, ($IconPath + ',0'), 'BushScript') } catch { }
                    try { [BushWin]::SetWindowIcons($h, $IconPath) } catch { }
                    $seen[$h] = $true
                }
            }
        }
        Start-Sleep -Milliseconds 2000
    }
} catch { }
""";

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
                  --blocklist=PATH    Extra blocklist file (hosts format, one domain per
                                      line, or ||domain^ rules). Can be repeated.
                  --no-adblock        Turn the ad blocker off (it is ON by default)
                  --no-launch         Start only the local proxy
                  --help              Show this help

                AdBlock:
                  Blocks ad, tracker and pop-up domains (and their subdomains) by name.
                  A built-in list is always loaded; if the file
                  ~/.Bush-local-browser/blocklist.txt exists it is loaded too.

                The proxy listens only on 127.0.0.1. HTTPS uses CONNECT tunneling;
                Bush cannot inspect or modify encrypted page contents, so blocking
                happens at the domain level.
                """);
    }

    private record Target(String host, int port) {
    }
}
