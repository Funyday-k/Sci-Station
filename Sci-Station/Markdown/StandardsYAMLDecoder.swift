import Foundation
import Yams

public nonisolated enum StandardsYAMLDecoderError: Error, LocalizedError, Sendable {
    case topLevelValueMustBeMapping
    case mappingKeyMustBeString(String)
    case unresolvedAlias(String)
    case cyclicAlias(String)
    case invalidMergedMapping

    public var errorDescription: String? {
        switch self {
        case .topLevelValueMustBeMapping:
            return "The YAML document must contain a mapping at its top level."
        case let .mappingKeyMustBeString(key):
            return "YAML mapping keys must be strings; found \(key)."
        case let .unresolvedAlias(anchor):
            return "YAML alias \(anchor) could not be resolved."
        case let .cyclicAlias(anchor):
            return "YAML alias \(anchor) contains a cycle."
        case .invalidMergedMapping:
            return "YAML merge keys must reference a mapping or a sequence of mappings."
        }
    }
}

/// Converts standards-compliant YAML into the value model shared by Markdown
/// frontmatter and other workspace metadata readers.
public nonisolated enum StandardsYAMLDecoder {
    public static func decodeMapping(_ contents: String) throws -> [String: FrontmatterValue] {
        guard let root = try Yams.compose(yaml: contents) else {
            return [:]
        }
        guard case let .mapping(mapping) = root else {
            throw StandardsYAMLDecoderError.topLevelValueMustBeMapping
        }
        var anchors: [String: Node] = [:]
        collectAnchors(in: root, into: &anchors)
        return try convertMapping(mapping, anchors: anchors, resolvingAliases: [])
    }

    private static func convert(
        _ node: Node,
        anchors: [String: Node],
        resolvingAliases: Set<String>
    ) throws -> FrontmatterValue {
        switch node {
        case let .scalar(scalar):
            switch node.tag.rawValue {
            case Tag.Name.null.rawValue:
                return .null
            case Tag.Name.bool.rawValue:
                return .boolean(node.bool ?? false)
            case Tag.Name.int.rawValue:
                if let value = node.int { return .integer(value) }
                return .string(scalar.string)
            case Tag.Name.float.rawValue:
                if let value = node.float { return .floatingPoint(value) }
                return .string(scalar.string)
            default:
                return .string(scalar.string)
            }
        case let .sequence(sequence):
            return .array(try sequence.map {
                try convert($0, anchors: anchors, resolvingAliases: resolvingAliases)
            })
        case let .mapping(mapping):
            return .object(try convertMapping(
                mapping,
                anchors: anchors,
                resolvingAliases: resolvingAliases
            ))
        case let .alias(alias):
            let name = alias.anchor.rawValue
            guard !resolvingAliases.contains(name) else {
                throw StandardsYAMLDecoderError.cyclicAlias(name)
            }
            guard let target = anchors[name] else {
                throw StandardsYAMLDecoderError.unresolvedAlias(name)
            }
            return try convert(
                target,
                anchors: anchors,
                resolvingAliases: resolvingAliases.union([name])
            )
        }
    }

    private static func convertMapping(
        _ mapping: Node.Mapping,
        anchors: [String: Node],
        resolvingAliases: Set<String>
    ) throws -> [String: FrontmatterValue] {
        var merged: [String: FrontmatterValue] = [:]
        var explicit: [(String, Node)] = []
        explicit.reserveCapacity(mapping.count)

        for (keyNode, valueNode) in mapping {
            guard case let .scalar(keyScalar) = keyNode else {
                throw StandardsYAMLDecoderError.mappingKeyMustBeString(keyNode.string ?? String(describing: keyNode))
            }
            if keyNode.tag.rawValue == Tag.Name.merge.rawValue || keyScalar.string == "<<" {
                for mapping in try mergedMappings(
                    from: valueNode,
                    anchors: anchors,
                    resolvingAliases: resolvingAliases
                ).reversed() {
                    merged.merge(mapping) { _, incoming in incoming }
                }
                continue
            }
            guard keyNode.tag.rawValue == Tag.Name.str.rawValue else {
                throw StandardsYAMLDecoderError.mappingKeyMustBeString(keyScalar.string)
            }
            explicit.append((keyScalar.string, valueNode))
        }

        for (key, valueNode) in explicit {
            merged[key] = try convert(
                valueNode,
                anchors: anchors,
                resolvingAliases: resolvingAliases
            )
        }
        return merged
    }

    private static func mergedMappings(
        from node: Node,
        anchors: [String: Node],
        resolvingAliases: Set<String>
    ) throws -> [[String: FrontmatterValue]] {
        let converted = try convert(
            node,
            anchors: anchors,
            resolvingAliases: resolvingAliases
        )
        switch converted {
        case let .object(mapping):
            return [mapping]
        case let .array(values):
            return try values.map { value in
                guard case let .object(mapping) = value else {
                    throw StandardsYAMLDecoderError.invalidMergedMapping
                }
                return mapping
            }
        default:
            throw StandardsYAMLDecoderError.invalidMergedMapping
        }
    }

    private static func collectAnchors(in node: Node, into anchors: inout [String: Node]) {
        if let anchor = node.anchor {
            anchors[anchor.rawValue] = node
        }
        switch node {
        case .scalar, .alias:
            return
        case let .sequence(sequence):
            for child in sequence { collectAnchors(in: child, into: &anchors) }
        case let .mapping(mapping):
            for (key, value) in mapping {
                collectAnchors(in: key, into: &anchors)
                collectAnchors(in: value, into: &anchors)
            }
        }
    }
}

/// Emits the shared metadata value model as standards-compliant YAML.
///
/// Callers can provide a preferred top-level order for human-facing files.
/// Object keys not present in that order are emitted lexicographically so
/// repeated writes stay deterministic.
public nonisolated enum StandardsYAMLEncoder {
    public static func encodeMapping(
        _ mapping: [String: FrontmatterValue],
        preferredKeyOrder: [String] = []
    ) throws -> String {
        let node = Node(
            orderedPairs(from: mapping, preferredKeyOrder: preferredKeyOrder),
            Tag(.map),
            .block
        )
        return try Yams.serialize(
            node: node,
            indent: 2,
            width: -1,
            allowUnicode: true,
            sequenceStyle: .block,
            mappingStyle: .block,
            newLineScalarStyle: .literal
        )
    }

    private static func orderedPairs(
        from mapping: [String: FrontmatterValue],
        preferredKeyOrder: [String]
    ) -> [(Node, Node)] {
        var seen = Set<String>()
        let preferred = preferredKeyOrder.compactMap { key -> String? in
            guard mapping[key] != nil, seen.insert(key).inserted else { return nil }
            return key
        }
        let remaining = mapping.keys.filter { seen.insert($0).inserted }.sorted()
        return (preferred + remaining).map { key in
            (keyNode(key), node(for: mapping[key] ?? .null))
        }
    }

    private static func node(for value: FrontmatterValue) -> Node {
        switch value {
        case let .string(value):
            let style: Node.Scalar.Style = value.contains("\n") ? .literal : .doubleQuoted
            return Node(value, Tag(.str), style)
        case let .boolean(value):
            return Node(value ? "true" : "false", Tag(.bool), .plain)
        case let .integer(value):
            return Node(String(value), Tag(.int), .plain)
        case let .floatingPoint(value):
            return Node(String(value), Tag(.float), .plain)
        case let .array(values):
            return Node(values.map(node(for:)), Tag(.seq), .block)
        case let .object(mapping):
            return Node(orderedPairs(from: mapping, preferredKeyOrder: []), Tag(.map), .block)
        case .null:
            return Node("null", Tag(.null), .plain)
        }
    }

    private static func keyNode(_ key: String) -> Node {
        Node(key, Tag(.str), .plain)
    }
}
