import UniformTypeIdentifiers

enum SupportedMediaTypes {
    private static func type(forExtension ext: String, fallback identifier: String) -> UTType {
        UTType(filenameExtension: ext) ?? UTType(importedAs: identifier)
    }

    static let fileImporterTypes: [UTType] = {
        let candidates: [UTType] = [
            .audiovisualContent,
            .movie,
            .video,
            .quickTimeMovie,
            .mpeg4Movie,
            .avi,
            type(forExtension: "m4v", fallback: "public.mpeg-4"),
            type(forExtension: "mkv", fallback: "org.matroska.mkv"),
            type(forExtension: "webm", fallback: "org.webmproject.webm"),
            type(forExtension: "mpg", fallback: "public.mpeg"),
            type(forExtension: "mpeg", fallback: "public.mpeg"),
            type(forExtension: "m2ts", fallback: "public.mpeg-2-transport-stream"),
            type(forExtension: "mts", fallback: "public.mpeg-2-transport-stream"),
            type(forExtension: "3gp", fallback: "public.3gpp"),
            .audio,
            .mp3,
            .wav,
            .aiff,
            type(forExtension: "aac", fallback: "public.aac-audio"),
            type(forExtension: "m4a", fallback: "public.mpeg-4-audio"),
            type(forExtension: "flac", fallback: "org.xiph.flac"),
            type(forExtension: "caf", fallback: "com.apple.coreaudio-format"),
            type(forExtension: "ogg", fallback: "org.xiph.ogg-audio"),
            type(forExtension: "opus", fallback: "org.xiph.opus"),
            .image,
            .png,
            .jpeg,
            .heic,
            .tiff,
            .gif,
            .bmp,
            type(forExtension: "webp", fallback: "org.webmproject.webp"),
            type(forExtension: "avif", fallback: "public.avif"),
        ]

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.identifier).inserted }
    }()

    static let dropTypes: [UTType] = [.fileURL, .movie, .video, .audio, .image]
}
