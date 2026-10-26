import java.nio.file.Files;
import java.nio.file.Path;
import org.omg.sysml.interactive.SysMLInteractive;
import org.omg.sysml.lang.sysml.*;
import java.util.*;

/** Uses the pinned OMG Pilot's parser, name resolver and semantic validator.
 * This does not execute modeled behavior or prove requirement satisfaction. */
public class Validate {
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            throw new IllegalArgumentException("Usage: Validate <library-directory> <model-files...>");
        }
        var interactive = SysMLInteractive.getInstance();
        interactive.loadLibrary(args[0]);
        var syntax = SysMLInteractive.createInstance();
        boolean syntaxErrors = false;
        boolean inventory = args.length > 1 && args[1].equals("--inventory");
        var model = new StringBuilder();
        var sources = new ArrayList<String>();
        var starts = new ArrayList<Integer>();
        int firstLine = 1;
        for (int i = inventory ? 2 : 1; i < args.length; i++) {
            String source = Files.readString(Path.of(args[i]));
            if (source.startsWith("\uFEFF")) source = source.substring(1);
            source = source.replace("\r\n", "\n").replace('\r', '\n');
            if (!source.endsWith("\n")) source += "\n";
            // Check each original file's grammar without resolving forward references.
            syntax.next(".sysml");
            syntax.parse(source);
            var parsed = ((org.eclipse.xtext.resource.XtextResource)syntax.getResource()).getParseResult();
            for (var node : parsed.getSyntaxErrors()) {
                System.out.printf("%s:%s: ERROR %s%n", args[i], node.getStartLine(),
                        node.getSyntaxErrorMessage().getMessage());
            }
            syntaxErrors |= parsed.hasSyntaxErrors();
            syntax.removeResource();
            sources.add(args[i]);
            starts.add(firstLine);
            model.append(source);
            firstLine += (int)source.chars().filter(c -> c == '\n').count();
        }
        if (syntaxErrors) System.exit(1);
        // Resolve the complete graph in one Pilot submission, including forward references.
        var result = interactive.process(model.toString());
        for (var issue : result.getIssues()) {
            var line = issue.getLineNumber();
            int source = 0;
            if (line != null) {
                while (source + 1 < starts.size() && line >= starts.get(source + 1)) source++;
            }
            System.out.printf("%s:%s: %s %s%n", sources.get(source),
                    line == null ? "?" : line - starts.get(source) + 1,
                    issue.getSeverity(), issue.getMessage());
        }
        if (result.getException() != null) result.getException().printStackTrace(System.err);
        if (result.hasErrors() || result.getException() != null) System.exit(1);
        if (inventory) {
            collectScope(interactive);
            var root = interactive.resolve("WstxArchitecture::physicalStation");
            if (!(root instanceof PartUsage)) throw new IllegalStateException("Missing physicalStation usage");
            for (var entry : rootParts) row("ROOTPART", entry);
            for (var entry : viewSemantics) row("VIEWSEMANTIC", entry);
            inspect((PartUsage)root, "physicalStation", 0);
        }
        System.out.println("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.");
    }
    static Set<String> rootParts = new TreeSet<>();
    static Set<String> viewSemantics = new TreeSet<>();
    static void collectScope(SysMLInteractive interactive) {
        var contents = interactive.getResource().getAllContents();
        while (contents.hasNext()) {
            var object = contents.next();
            if (object instanceof PartUsage part && !part.isLibraryElement() && !(part instanceof Connector) && !(part instanceof ViewUsage)
                    && part.getOwningNamespace() instanceof org.omg.sysml.lang.sysml.Package) {
                rootParts.add(part.getQualifiedName());
            }
            if (object instanceof ViewUsage view && !view.isLibraryElement()) {
                for (var feature : view.getOwnedFeature()) {
                    if (feature instanceof Connector || feature instanceof PartUsage && !(feature instanceof ViewUsage)) {
                        viewSemantics.add(view.getQualifiedName() + "::" + name(feature));
                    }
                }
            }
        }
    }

    // Export resolved semantic objects, never source text or viewer output.
    static String name(Element element) {
        return element.getName() == null ? "" : element.getName();
    }
    static String chain(Feature feature) {
        var chains = feature.getChainingFeature();
        if (!chains.isEmpty()) {
            return String.join(".", chains.stream().map(Validate::chain).toList());
        }
        var target = feature.getFeatureTarget();
        if (target != null && target != feature && name(feature).isEmpty()) return chain(target);
        return name(feature);
    }
    static boolean project(Feature feature) {
        var qualified = feature.getQualifiedName();
        return qualified != null && qualified.startsWith("WstxArchitecture::");
    }
    static void row(String... fields) {
        System.out.println("AST\t" + String.join("\t", fields));
    }
    static String bounds(Feature feature) {
        for (var multiplicity : feature.multiplicities()) {
            if (multiplicity instanceof MultiplicityRange range && range.getOwner() == feature) {
                return (range.getLowerBound() == null ? 0 : range.valueOf(range.getLowerBound())) + ":" + range.valueOf(range.getUpperBound());
            }
        }
        return "1:1";
    }
    static void inspect(PartUsage part, String path, int depth) {
        if (depth > 16) throw new IllegalStateException("Recursive architecture decomposition");
        row(part instanceof ConnectionUsage ? "CONNECTION" : part.isReference() && !part.getOwnedSubsetting().isEmpty() ? "REF" : "PART", path, String.join(",", part.getDefinition().stream().map(Element::getQualifiedName).toList()),
            bounds(part), String.valueOf(part.isVariation()),
            String.join(",", part.getOwnedSubsetting().stream().map(x -> chain(x.getSubsettedFeature())).toList()));
        if (part.isReference() && !part.getOwnedSubsetting().isEmpty()) return;
        for (var feature : part.getFeature()) {
            if (!project(feature)) continue;
            if (feature instanceof Connector connector) {
                var ends = connector.getRelatedFeature();
                row("EDGE", path, name(connector), connector instanceof BindingConnector ? "binding" : "connection", String.join("|", ends.stream().map(Validate::chain).toList()));
                if (connector instanceof ConnectionUsage connection) inspect(connection, path + "." + name(connection), depth + 1);
            } else if (feature instanceof PortUsage port) {
                var portPath = path + "." + name(port);
                row("PORT", portPath, String.join(",", port.getPortDefinition().stream().map(Element::getQualifiedName).toList()));
                for (var definition : port.getPortDefinition()) {
                    boolean conjugated = definition instanceof ConjugatedPortDefinition;
                    var original = conjugated ? ((ConjugatedPortDefinition)definition).getOriginalPortDefinition() : definition;
                    for (var item : original.getFeature()) {
                        if (item instanceof Connector connector && project(item)) {
                            row("EDGE", portPath, name(connector), connector instanceof BindingConnector ? "binding" : "connection", String.join("|", connector.getRelatedFeature().stream().map(Validate::chain).toList()));
                        }
                        if (item instanceof ItemUsage && project(item)) {
                            var direction = String.valueOf(item.getDirection());
                            if (conjugated) direction = direction.equals("in") ? "out" : direction.equals("out") ? "in" : direction;
                            row("ITEM", portPath, name(item), direction,
                                String.join(",", item.getType().stream().map(Element::getQualifiedName).toList()));
                        }
                    }
                }
            } else if (feature instanceof PartUsage child) {
                inspect(child, path + "." + name(child), depth + 1);
            }
        }
        if (part.isVariation()) {
            for (var variant : part.getVariant()) inspect((PartUsage)variant, path + "." + name(variant), depth + 1);
            row("VARIANTS", path, String.join(",", part.getVariant().stream().map(Validate::name).toList()));
        }
    }
}
