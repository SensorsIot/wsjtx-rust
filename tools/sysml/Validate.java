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
        // --export <names-file>: every element of the model files and the resolution of
        // each name of the file, after the same validation (CL-014-17).
        boolean export = args.length > 2 && args[1].equals("--export");
        var model = new StringBuilder();
        var sources = new ArrayList<String>();
        var starts = new ArrayList<Integer>();
        int firstLine = 1;
        for (int i = inventory ? 2 : export ? 3 : 1; i < args.length; i++) {
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
            modelResource = interactive.getResource();
            collectScope(interactive);
            var root = interactive.resolve("WstxArchitecture::physicalStation");
            if (!(root instanceof PartUsage)) throw new IllegalStateException("Missing physicalStation usage");
            for (var entry : rootParts) row("ROOTPART", entry);
            for (var entry : viewSemantics) row("VIEWSEMANTIC", entry);
            inspect((PartUsage)root, "physicalStation", 0);
        }
        if (export) {
            modelResource = interactive.getResource();
            sourceStarts = starts;
            exportModel(interactive, Files.readAllLines(Path.of(args[2])));
        }
        System.out.println("OMG Pilot 0.62.0 syntax/name/semantic validation passed; behavior not executed.");
    }
    static Set<String> rootParts = new TreeSet<>();
    static Set<String> viewSemantics = new TreeSet<>();
    // The one resource that holds every model file of the submission. Everything the pinned
    // model library declares lies in other resources; a `library package` written in a model
    // file lies in this one and is inventoried like any other package.
    static org.eclipse.emf.ecore.resource.Resource modelResource;
    static void collectScope(SysMLInteractive interactive) {
        var contents = modelResource.getAllContents();
        while (contents.hasNext()) {
            var object = contents.next();
            if (object instanceof PartUsage part && !(part instanceof Connector) && !(part instanceof ViewUsage)
                    && part.getOwningNamespace() instanceof org.omg.sysml.lang.sysml.Package) {
                rootParts.add(String.valueOf(part.getQualifiedName()));
            }
            if (object instanceof ViewUsage view) {
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
    /** Whether a model file declares the feature, whatever its package or the package of
     * its definition; a feature of the pinned model library is not. A connector's end is
     * part of its connector, not a feature of the deployment. */
    static boolean project(Feature feature) {
        return feature.eResource() == modelResource && !feature.isEnd();
    }
    /** A port definition by qualified name; a conjugate as `~` and its original's name. */
    static String portDefinition(PortDefinition definition) {
        return definition instanceof ConjugatedPortDefinition conjugate
            ? "~" + conjugate.getOriginalPortDefinition().getQualifiedName() : definition.getQualifiedName();
    }
    /** The qualified names of the part's definitions and of every type they specialize,
     * directly or through other types, in any package. */
    static String kinds(PartUsage part) {
        var found = new TreeSet<String>();
        for (var definition : part.getDefinition()) supertypes(definition, found);
        return String.join(",", found);
    }
    static void supertypes(Type type, Set<String> found) {
        if (type == null || type.getQualifiedName() == null || !found.add(type.getQualifiedName())) return;
        for (var specialization : type.getOwnedSpecialization()) supertypes(specialization.getGeneral(), found);
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
            String.join(",", part.getOwnedSubsetting().stream().map(x -> chain(x.getSubsettedFeature())).toList()),
            kinds(part));
        if (part.isReference() && !part.getOwnedSubsetting().isEmpty()) return;
        for (var feature : part.getFeature()) {
            if (!project(feature)) continue;
            if (feature instanceof Connector connector) {
                var ends = connector.getRelatedFeature();
                row("EDGE", path, name(connector), connector instanceof BindingConnector ? "binding" : "connection", String.join("|", ends.stream().map(Validate::chain).toList()));
                if (connector instanceof ConnectionUsage connection) inspect(connection, path + "." + name(connection), depth + 1);
            } else if (feature instanceof PortUsage port) {
                var portPath = path + "." + name(port);
                row("PORT", portPath, String.join(",", port.getPortDefinition().stream().map(Validate::portDefinition).toList()));
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

    // ---- Export of every element (CL-014-17, `tools/sysml.py equivalence`) ----
    // An entry is an element that has a declared name, as has each of its owners up to a
    // top-level package; it is written with its key (the declared names from the top-level
    // package down). Everything unnamed is written as part of its nearest entry, in
    // declaration order; an unnamed member of a top-level package is written as an item.
    // Imports and alias memberships are left out: their effect is in the resolved targets.
    static List<Integer> sourceStarts;
    static Map<Element, List<String>> keys = new IdentityHashMap<>();

    static void exportModel(SysMLInteractive interactive, List<String> names) {
        Namespace global = null;
        for (var root : modelResource.getContents()) {
            if (!(root instanceof Namespace namespace)) continue;
            if (global == null) global = namespace;
            for (var relationship : namespace.getOwnedRelationship()) {
                // A member of no package (a file's header comment): an item, as a package's.
                if (kept(relationship) && relationship.getOwnedRelatedElement().stream().noneMatch(owned -> owned.getDeclaredName() != null)) {
                    var facts = new ArrayList<String>();
                    facts(relationship, "", relationship, facts, true);
                    exportRow("ITEM", "{\"file\":" + fileOf(relationship) + ",\"facts\":[" + String.join(",", facts) + "]}");
                    continue;
                }
                for (var element : relationship.getOwnedRelatedElement()) {
                    if (element.getDeclaredName() != null) {
                        exportRow("PACKAGE", "{\"name\":" + json(element.getDeclaredName()) + ",\"file\":" + fileOf(element) + "}");
                    }
                    for (var member : element.getOwnedRelationship()) {
                        if (kept(member)) {
                            var facts = new ArrayList<String>();
                            facts(member, "", member, facts, true);
                            exportRow("ITEM", "{\"file\":" + fileOf(member) + ",\"facts\":[" + String.join(",", facts) + "]}");
                        }
                    }
                }
            }
        }
        var contents = modelResource.getAllContents();
        while (contents.hasNext()) {
            if (contents.next() instanceof Element element && entry(element)) {
                var facts = new ArrayList<String>();
                var owning = element.getOwningRelationship();
                if (owning != null) facts(owning, "via", element, facts, false);
                facts(element, "", element, facts, true);
                exportRow("ENTRY", "{\"key\":" + jsonList(segments(element)) + ",\"file\":" + fileOf(element)
                    + ",\"facts\":[" + String.join(",", facts) + "]}");
            }
        }
        for (var name : names) {
            if (name.isBlank()) continue;
            var target = resolveName(interactive, global, name.strip());
            exportRow("RESOLVE", "{\"name\":" + json(name.strip()) + ",\"id\":" + (target == null ? "null" : json(id(target, null))) + "}");
        }
    }

    /** The element a qualified name resolves to: the Pilot's resolution from the global
     * namespace (memberships visible there, imports, aliases and re-exports included), else
     * the interactive's own lookup; null when neither finds one. */
    static Element resolveName(SysMLInteractive interactive, Namespace global, String name) {
        if (global != null) {
            try {
                var method = global.getClass().getMethod("resolveGlobal", String.class);
                if (method.invoke(global, name) instanceof Membership membership && membership.getMemberElement() != null) {
                    return membership.getMemberElement();
                }
            } catch (Throwable ignored) {
                // No such operation in this Pilot or no match: fall through.
            }
        }
        try {
            return interactive.resolve(name);
        } catch (Throwable ignored) {
            return null;
        }
    }

    static void exportRow(String kind, String body) {
        System.out.println("EXPORT\t" + kind + "\t" + body);
    }

    static int fileOf(org.eclipse.emf.ecore.EObject object) {
        for (var current = object; current != null; current = current.eContainer()) {
            var node = org.eclipse.xtext.nodemodel.util.NodeModelUtils.getNode(current);
            if (node != null) {
                int line = node.getStartLine(), source = 0;
                while (source + 1 < sourceStarts.size() && line >= sourceStarts.get(source + 1)) source++;
                return source;
            }
        }
        return -1;
    }

    /** The declared names from the top-level element down; null when the element or an owner
     * below the top level has none, or the element is outside the model files. */
    static List<String> segments(Element element) {
        if (element == null || element.eResource() != modelResource) return null;
        var key = element;
        if (keys.containsKey(key)) return keys.get(key);
        List<String> found = null;
        var owner = element.getOwner();
        if (owner != null && element.getDeclaredName() != null) {
            if (owner.getOwner() == null) {
                found = new ArrayList<>(List.of(segment(element.getDeclaredName())));
            } else {
                var above = segments(owner);
                if (above != null) {
                    found = new ArrayList<>(above);
                    found.add(segment(element.getDeclaredName()));
                }
            }
        }
        keys.put(key, found);
        return found;
    }

    static String segment(String name) {
        return name.matches("[A-Za-z_][A-Za-z0-9_]*") ? name : "'" + name.replace("\\", "\\\\").replace("'", "\\'") + "'";
    }

    static boolean entry(org.eclipse.emf.ecore.EObject object) {
        if (!(object instanceof Element element)) return false;
        var found = segments(element);
        return found != null && found.size() > 1;
    }

    static boolean top(Element element) {
        return element.eResource() == modelResource && element.getOwner() != null && element.getOwner().getOwner() == null;
    }

    /** An import or an alias: a membership, compared through the targets it lets resolve.
     * An expose is no such membership: what a view exposes is compared. */
    static boolean free(org.eclipse.emf.ecore.EObject object) {
        return object instanceof Import && !(object instanceof Expose)
            || object instanceof Membership membership && !(membership instanceof OwningMembership) && membership.getMemberName() != null;
    }

    /** A relationship that owns entries only: written with each entry it owns ("via"). */
    static boolean holdsEntry(org.eclipse.emf.ecore.EObject object) {
        if (!(object instanceof Relationship relationship)) return false;
        var owned = relationship.getOwnedRelatedElement();
        return !owned.isEmpty() && owned.stream().allMatch(Validate::entry);
    }

    static boolean kept(org.eclipse.emf.ecore.EObject object) {
        return !free(object) && !holdsEntry(object) && !entry(object);
    }

    /** One step of a path: the class and the index among the kept elements of the same
     * containment, so that an import or an entry in between moves no index. */
    static String step(org.eclipse.emf.ecore.EObject object) {
        var container = object.eContainer();
        var feature = object.eContainmentFeature();
        int index = 0;
        if (feature.isMany()) {
            for (var sibling : (List<?>)container.eGet(feature)) {
                if (sibling == object) break;
                if (sibling instanceof org.eclipse.emf.ecore.EObject other && kept(other)) index++;
            }
        }
        return object.eClass().getName() + "[" + index + "]";
    }

    static String localPath(org.eclipse.emf.ecore.EObject object, org.eclipse.emf.ecore.EObject ancestor) {
        var steps = new ArrayList<String>();
        for (var current = object; current != null && current != ancestor; current = current.eContainer()) steps.add(0, step(current));
        return String.join("/", steps);
    }

    /** A reference target: `#path` inside the element being written, `M:key[#path]` in an
     * entry, `P` a top-level package, `T#path` inside a package-level item, `L:name` an
     * element of the model library. */
    static String id(org.eclipse.emf.ecore.EObject target, org.eclipse.emf.ecore.EObject current) {
        if (!(target instanceof Element element)) return "?" + target.eClass().getName();
        if (element.eResource() != modelResource) {
            var name = element.getQualifiedName();
            return "L:" + (name != null ? name : element.eClass().getName() + ":" + name(element));
        }
        for (var ancestor = (org.eclipse.emf.ecore.EObject)element; ancestor != null; ancestor = ancestor.eContainer()) {
            if (ancestor == current) return "#" + localPath(element, ancestor);
            if (ancestor instanceof Element owner) {
                if (entry(owner)) {
                    return "M:" + String.join("::", segments(owner)) + (owner == element ? "" : "#" + localPath(element, owner));
                }
                if (owner.getOwner() == null || top(owner)) {
                    if (owner == element) return "P";
                    var path = localPath(element, owner);
                    return "T#" + (path.contains("/") ? path.substring(path.indexOf('/') + 1) : "");
                }
            }
        }
        return "?";
    }

    /** The facts of one object as JSON arrays [path, type, feature, value]: its class, its
     * stored attributes, its stored references as target ids and, when `contained`, the
     * facts of each kept object it contains. Comment bodies are typed "text". */
    static void facts(org.eclipse.emf.ecore.EObject object, String path, org.eclipse.emf.ecore.EObject current,
                      List<String> out, boolean contained) {
        out.add(fact(path, "kind", "", json(object.eClass().getName())));
        for (var feature : object.eClass().getEAllStructuralFeatures()) {
            if (feature.isDerived() || feature.isTransient()) continue;
            var name = feature.getName();
            if (name.equals("elementId") || name.equals("isImpliedIncluded")) continue;
            if (feature instanceof org.eclipse.emf.ecore.EReference reference) {
                if (reference.isContainer()) continue;
                var values = new ArrayList<org.eclipse.emf.ecore.EObject>();
                var value = object.eGet(reference);
                if (value instanceof List<?> list) {
                    for (var item : list) if (item instanceof org.eclipse.emf.ecore.EObject target) values.add(target);
                } else if (value instanceof org.eclipse.emf.ecore.EObject target) {
                    values.add(target);
                }
                if (reference.isContainment()) {
                    if (!contained) continue;
                    for (var child : values) {
                        if (kept(child)) facts(child, path.isEmpty() ? step(child) : path + "/" + step(child), current, out, true);
                    }
                } else if (!values.isEmpty()) {
                    out.add(fact(path, "ref", name, jsonList(values.stream().map(target -> id(target, current)).toList())));
                }
            } else {
                if (!object.eIsSet(feature)) continue;
                var value = object.eGet(feature);
                var type = object instanceof Comment && name.equals("body") ? "text" : "attr";
                out.add(fact(path, type, name, json(String.valueOf(value))));
            }
        }
    }

    static String fact(String path, String type, String feature, String value) {
        return "[" + json(path) + "," + json(type) + "," + json(feature) + "," + value + "]";
    }

    static String jsonList(List<String> values) {
        return "[" + String.join(",", values.stream().map(Validate::json).toList()) + "]";
    }

    /** A JSON string in ASCII: every other character escaped, whatever the console's code page. */
    static String json(String text) {
        if (text == null) return "null";
        var out = new StringBuilder("\"");
        for (char character : text.toCharArray()) {
            switch (character) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (character < 0x20 || character > 0x7e) out.append(String.format("\\u%04x", (int)character));
                    else out.append(character);
                }
            }
        }
        return out.append('"').toString();
    }
}
