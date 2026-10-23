package bushscript;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public final class BushscriptUninstaller {

    public static void main(String[] args) {
        System.out.println("========================================");
        System.out.println("   BushScript has been discontinued");
        System.out.println("========================================");
        System.out.println();
        System.out.println("Starting BushScript uninstall...");
        System.out.println();

        Path profile = Path.of(
                System.getProperty("user.home"),
                ".Bush-local-browser"
        );

        // Remove the BushScript browser profile and its stored data.
        try {
            if (Files.exists(profile)) {
                deleteDirectory(profile);
                System.out.println("Removed browser profile: " + profile);
            } else {
                System.out.println("Browser profile not found.");
            }
        } catch (IOException e) {
            System.err.println(
                    "Could not remove browser profile: " + e.getMessage()
            );
        }

        // Remove optional helper files from the current directory.
        List<String> files = List.of(
                "Bushscript.class",
                "Bushscript$Target.class",
                "bushpolish.ps1",
                "bush.ico"
        );

        for (String name : files) {
            try {
                if (Files.deleteIfExists(Path.of(name))) {
                    System.out.println("Removed: " + name);
                }
            } catch (IOException e) {
                System.err.println(
                        "Could not remove " + name + ": " + e.getMessage()
                );
            }
        }

        System.out.println();
        System.out.println("BushScript uninstall steps completed.");
    }

    private static void deleteDirectory(Path directory)
            throws IOException {
        if (!Files.exists(directory)) {
            return;
        }

        try (var paths = Files.walk(directory)) {
            for (Path path : paths
                    .sorted(java.util.Comparator.reverseOrder())
                    .toList()) {
                Files.deleteIfExists(path);
            }
        }
    }
}
