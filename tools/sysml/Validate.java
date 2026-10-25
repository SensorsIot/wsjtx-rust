import java.nio.file.Files;
import java.nio.file.Path;
import org.omg.sysml.interactive.SysMLInteractive;

/** Uses the pinned OMG Pilot's parser, name resolver and semantic validator.
 * This does not execute modeled behavior or prove requirement satisfaction. */
public class Validate {
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            throw new IllegalArgumentException("Usage: Validate <library-directory> <ordered-model-files...>");
        }
        var interactive = SysMLInteractive.getInstance();
        interactive.loadLibrary(args[0]);
        boolean failed = false;
        for (int i = 1; i < args.length; i++) {
            String source = Files.readString(Path.of(args[i]));
            if (source.startsWith("\uFEFF")) source = source.substring(1);
            var result = interactive.process(source);
            for (var issue : result.getIssues()) {
                System.out.printf("%s:%s: %s %s%n", args[i], issue.getLineNumber(), issue.getSeverity(), issue.getMessage());
            }
            if (result.getException() != null) {
                result.getException().printStackTrace(System.err);
                failed = true;
            }
            failed |= result.hasErrors();
        }
        if (failed) System.exit(1);
        System.out.println("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.");
    }
}
