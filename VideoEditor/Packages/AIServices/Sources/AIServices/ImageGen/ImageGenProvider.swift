import Foundation

/// Protocol for AI image generation providers (GPT Image, Nano Banana, etc.)
public protocol ImageGenProvider: Sendable {
    var name: String { get }

    /// Generate an image from a text prompt with optional reference images.
    func generateImage(
        prompt: String,
        referenceImages: [Data],
        size: ImageGenSize
    ) async throws -> Data
}

/// Output size for generated images.
public enum ImageGenSize: String, Sendable {
    case thumbnail = "1536x1024"   // YouTube thumbnail (landscape)
    case square = "1024x1024"      // Instagram square (closest supported)
    case portrait = "1024x1536"    // Instagram portrait (closest supported)
}

/// Request to generate thumbnails.
public struct ThumbnailRequest: Sendable {
    public let title: String
    public let subtitle: String?
    public let description: String?
    public let hostNames: [String]
    public let hostPhotos: [Data]
    public let style: ThumbnailStyle
    public let layout: ThumbnailLayout
    public let promptOverride: String?
    public let countPerProvider: Int
    public let providerFilter: ProviderFilter

    public init(
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        hostNames: [String] = [],
        hostPhotos: [Data] = [],
        style: ThumbnailStyle = .bold,
        layout: ThumbnailLayout = .splitPanel,
        promptOverride: String? = nil,
        countPerProvider: Int = 2,
        providerFilter: ProviderFilter = .both
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.hostNames = hostNames
        self.hostPhotos = hostPhotos
        self.style = style
        self.layout = layout
        self.promptOverride = promptOverride
        self.countPerProvider = countPerProvider
        self.providerFilter = providerFilter
    }
}

public enum ThumbnailStyle: String, Sendable {
    case bold, minimal, dramatic, vibrant
}

public enum ThumbnailLayout: String, Sendable {
    case splitPanel = "split_panel"
    case hostsLeft = "hosts_left"
    case centered = "centered"
    case textHeavy = "text_heavy"

    public var promptDescription: String {
        switch self {
        case .splitPanel:
            return "Split panel layout: Host A on the left side with their own color zone, Host B on the right side with their own color zone, episode title text centered between them"
        case .hostsLeft:
            return "Both hosts positioned on the left side of the image, large bold title text on the right side"
        case .centered:
            return "Title text prominently centered at the top, both hosts below in a face-off style arrangement"
        case .textHeavy:
            return "Small host photos in the top-left corner, massive bold title text dominating the entire thumbnail"
        }
    }
}

public enum ProviderFilter: String, Sendable {
    case both, openai, gemini
}

/// Result from thumbnail generation.
public struct GeneratedThumbnail: Sendable {
    public let imageData: Data
    public let provider: String
    public let index: Int

    public init(imageData: Data, provider: String, index: Int) {
        self.imageData = imageData
        self.provider = provider
        self.index = index
    }
}
