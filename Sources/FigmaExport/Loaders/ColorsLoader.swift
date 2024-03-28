import FigmaAPI
import FigmaExportCore

/// Loads colors from Figma
final class ColorsLoader {
    
    private let client: Client
    private let figmaParams: Params.Figma
    private let colorParams: Params.Common.Colors?

    init(client: Client, figmaParams: Params.Figma, colorParams: Params.Common.Colors?) {
        self.client = client
        self.figmaParams = figmaParams
        self.colorParams = colorParams
    }

    func load(filter: String?) throws -> (light: [Color], dark: [Color]?, lightHC: [Color]?, darkHC: [Color]?) {
        guard let useSingleFile = colorParams?.useSingleFile, useSingleFile else {
            return try loadColorsFromLightAndDarkFile(filter: filter)
        }
        return try loadColorsFromSingleFile(filter: filter)
    }

    private func loadColorsFromLightAndDarkFile(filter: String?) throws -> (light: [Color],
                                                                            dark: [Color]?,
                                                                            lightHC: [Color]?,
                                                                            darkHC: [Color]?) {
        let lightColors = try loadColors(fileId: figmaParams.lightFileId, filter: filter)
        let darkColors = try figmaParams.darkFileId.map { try loadColors(fileId: $0, filter: filter) }
        let lightHighContrastColors = try figmaParams.lightHighContrastFileId.map { try loadColors(fileId: $0, filter: filter) }
        let darkHighContrastColors = try figmaParams.darkHighContrastFileId.map { try loadColors(fileId: $0, filter: filter) }
        return (lightColors, darkColors, lightHighContrastColors, darkHighContrastColors)
    }

    private func loadColorsFromSingleFile(filter: String?) throws -> (light: [Color],
                                                                      dark: [Color]?,
                                                                      lightHC: [Color]?,
                                                                      darkHC: [Color]?) {
        let colors = try loadColors(fileId: figmaParams.lightFileId, filter: filter)

        let lightPrefix = colorParams?.lightModePrefix
        let darkPrefix = colorParams?.darkModePrefix
        let lightSuffix = colorParams?.lightModeSuffix
        let darkSuffix = colorParams?.darkModeSuffix
        let lightHCPrefix = colorParams?.lightHCModePrefix ?? "lightHC_"
        let darkHCPrefix = colorParams?.darkHCModePrefix ?? "darkHC_"
        let lightHCSuffix = colorParams?.lightHCModeSuffix ?? "_lightHC"
        let darkHCSuffix = colorParams?.darkHCModeSuffix ?? "_darkHC"

        let lightColors = filteredColors(colors, prefix: lightPrefix, suffix: lightSuffix)
        let darkColors = filteredColors(colors, prefix: darkPrefix, suffix: darkSuffix)
        let lightHCColors = filteredColors(colors, prefix: lightHCPrefix, suffix: lightHCSuffix)
        let darkHCColors = filteredColors(colors, prefix: darkHCPrefix, suffix: darkHCSuffix)
        return (lightColors, darkColors, lightHCColors, darkHCColors)
    }

    private func filteredColors(_ colors: [Color], prefix: String?, suffix: String?) -> [Color] {
        let filteredColors = colors
            .filter {
                if let prefix, let suffix {
                    return $0.name.hasPrefix(prefix) && $0.name.hasSuffix(suffix)
                } else if let prefix {
                    return $0.name.hasPrefix(prefix)
                } else if let suffix {
                    return $0.name.hasSuffix(suffix)
                } else {
                    return true
                }
            }
            .map { color -> Color in
                var newColor = color
                newColor.name = String(color.name.dropFirst(prefix?.count ?? 0).dropLast(suffix?.count ?? 0))
                return newColor
            }
        return filteredColors
    }
    
    private func loadColors(fileId: String, filter: String?) throws -> [Color] {
        var styles = try loadStyles(fileId: fileId)
        
        if let filter {
            let assetsFilter = AssetsFilter(filter: filter)
            styles = styles.filter { style -> Bool in
                assetsFilter.match(name: style.name)
            }
        }
        
        guard !styles.isEmpty else {
            throw FigmaExportError.stylesNotFound
        }
        
        let nodes = try loadNodes(fileId: fileId, nodeIds: styles.map { $0.nodeId } )
        return nodesAndStylesToColors(nodes: nodes, styles: styles)
    }
    
    /// Соотносит массив Style и Node чтобы получит массив Color
    private func nodesAndStylesToColors(nodes: [NodeId: Node], styles: [Style]) -> [Color] {
        return styles.compactMap { style -> Color? in
            guard let node = nodes[style.nodeId] else { return nil }
            guard let fill = node.document.fills.first?.asSolid else { return nil }
            let alpha: Double = fill.opacity ?? fill.color.a
            let platform = Platform(rawValue: style.description)
            
            return Color(name: style.name, platform: platform,
                         red: fill.color.r, green: fill.color.g, blue: fill.color.b, alpha: alpha)
        }
    }
    
    private func loadStyles(fileId: String) throws -> [Style] {
        let endpoint = StylesEndpoint(fileId: fileId)
        let styles = try client.request(endpoint)
        return styles.filter {
            $0.styleType == .fill && useStyle($0)
        }
    }
    
    private func useStyle(_ style: Style) -> Bool {
        guard !style.description.isEmpty else {
            return true // Цвет общий
        }
        return !style.description.contains("none")
    }
    
    private func loadNodes(fileId: String, nodeIds: [String]) throws -> [NodeId: Node] {
        let endpoint = NodesEndpoint(fileId: fileId, nodeIds: nodeIds)
        return try client.request(endpoint)
    }
}
