
import FoundationModels
import PhotosUI
import SwiftUI

struct ImageEditView: View {
    @State private var manager = ImageEditManager()
    @State private var scrollPosition: ScrollPosition = .init()
    @State private var entry: String = ""
    @State private var entryHeight: CGFloat = 24
    @State private var error: Error?

    @State private var selections: [PhotosPickerItem] = []
    @State private var images: [Data] = []

    var body: some View {
        let transcript = manager.session?.transcript ?? Transcript()

        ScrollViewReader { proxy in
            List {
                Text("FoundationModel + Image")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)

                if transcript.isEmpty {
                    Text("Enter something to start")
                }
                ForEach(transcript, id: \.id) { transcript in
                    self.transcriptView(transcript)
                        .id(transcript.id)
                }

                if manager.session?.isResponding == true {
                    ProgressView()
                        .padding(.all, 16)
                }

                if let error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                }
            }
            .font(.headline)
            .scrollTargetLayout()
            .frame(maxWidth: .infinity)
            .scrollPosition($scrollPosition, anchor: .bottom)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onChange(
                of: transcript,
                initial: true,
                {
                    if let last = transcript.last {
                        proxy.scrollTo(last.id)
                    }
                }
            )
        }
        .frame(minWidth: 480, minHeight: 400)
        .padding(.bottom, entryHeight)
        .task(id: self.selections) {
            guard !self.selections.isEmpty else {
                self.images = []
                return
            }
            var datas: [Data] = []

            for selection in selections {
                if let data = try? await selection.loadTransferable(
                    type: Data.self
                ) {
                    datas.append(data)
                }
            }
            self.images = datas
        }
        .overlay(
            alignment: .bottom,
            content: {
                VStack(alignment: .leading) {
                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selections,
                            label: {
                                Image(systemName: "plus")
                            }
                        )

                        Text("\(images.count) images added")

                    }
                    .foregroundStyle(.black)

                    HStack(spacing: 12) {
                        TextEditor(text: $entry)
                            .onSubmit({
                                self.sendPrompt()
                            })
                            .textEditorStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundStyle(.background.opacity(0.8))
                            .padding(.all, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(.gray, style: .init(lineWidth: 1))
                                    .fill(.white)
                            )
                            .frame(maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(
                            action: {
                                self.sendPrompt()
                            },
                            label: {
                                Image(systemName: "paperplane.fill")
                            }
                        )
                        .buttonStyle(.glass)
                        .foregroundStyle(.blue)
                        .disabled(self.manager.session?.isResponding ?? false)

                    }

                }
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(.yellow.opacity(0.2))
                .background(.white)
                .onGeometryChange(
                    for: CGFloat.self,
                    of: {
                        $0.size.height
                    },
                    action: { old, new in
                        self.entryHeight = new
                    }
                )
            }
        )
    }

    private func sendPrompt() {
        self.error = nil
        let entry = self.entry.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = self.images.map({ CIImage(data: $0) }).filter({ $0 != nil }
        ).map({ $0! })
        guard !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        self.entry = ""
        self.images = []
        self.selections = []
        Task {
            do {
                try await self.manager.respond(to: entry, images: images)
            } catch (let error) {
                self.error = error
            }
        }

    }

    @ContentBuilder
    private func transcriptView(_ entry: Transcript.Entry) -> some View {
        Group {
            switch entry {
            case .instructions(let instructions):
                Text("**Instructions**: \(instructions.description)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

            case .prompt(let prompt):
                VStack(alignment: .leading, spacing: 8) {
                    Text("**User prompt**")
                    ForEach(prompt.segments) { segment in
                        self.segmentView(segment)
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.all, 16)
                .background(RoundedRectangle(cornerRadius: 24).fill(.yellow))
                .padding(.leading, 64)

            case .toolCalls(let toolCalls):
                Text("**Tool call**: \(toolCalls.description)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

            case .toolOutput(let toolOutput):
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Tool Output**")
                    ForEach(toolOutput.segments) { segment in
                        self.segmentView(segment)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)

            case .response(let response):
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Assistant Response**")
                    ForEach(response.segments) { segment in
                        self.segmentView(segment)
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.all, 16)
                .background(RoundedRectangle(cornerRadius: 24).fill(.green))
                .padding(.trailing, 64)

            case .reasoning(let reasoning):
                Text("**Reasoning**: \(reasoning.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

            default:
                Text("Unknown transcript entry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)

            }
        }
        .listRowInsets(.all, 0)
        .padding(.vertical, 16)
        .listRowSeparator(.hidden)
    }

    @ContentBuilder
    private func segmentView(_ segment: Transcript.Segment) -> some View {
        switch segment {
        case .text(let textSegment):
            Text(textSegment.content)

        case .structure(let structuredSegment):
            Text(structuredSegment.content.jsonString)

        case .attachment(let attachmentSegment):
            switch attachmentSegment.content {
            case .image(let image):
                VStack(spacing: 4) {
                    Image(attachement: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                    Text(
                        "size: \(image.cgImage.width) * \(image.cgImage.height)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            default:
                Text("Unknown attachment")
            }
        case .custom(let customSegment):
            Text("Custom Segment: \(customSegment.description)")
        default:
            Text("Unknown Segment")

        }
    }
}

@Observable
nonisolated class ImageEditManager {
    var session: LanguageModelSession?
    private var resizeImageTool: ResizeImageTool?

    init() {
        let tool = ResizeImageTool(getSessionTranscript: {
            return self.session?.transcript
        })
        self.resizeImageTool = tool
        let session = LanguageModelSession(tools: [tool])
        self.session = session
    }

    func respond(to prompt: String, images: [CIImage]) async throws {
        guard let session else {
            return
        }
        if session.isResponding {
            return
        }
        let _ =
            try await session.respond(  // NOTE: using structured output here will result in session calling tool repetitively, ie:
            //
            // respond(to:images:)
            // call(arguments:) Arguments(image: FoundationModels.ImageReference(attachmentLabel: "image_0"), width: 1000.0, height: 1000.0)
            // call(arguments:) Arguments(image: FoundationModels.ImageReference(attachmentLabel: "image_0"), width: 1000.0, height: 1000.0)
            // call(arguments:) Arguments(image: FoundationModels.ImageReference(attachmentLabel: "image_0"), width: 1000.0, height: 1000.0)
            //
            // PS: Tool calls don't throw any error
            // generating: StructuredResponse.self,
            ) {
                prompt
                for image in images {
                    Attachment(image)
                        // explicit label required.
                        // Otherwise, the ImageReference attachment label will not match the automatically generated one
                        .label("image_\(UUID())")
                }
            }
    }
}

// For some reasons, when using structured output with Attachment,
// Foundation models will start calling tools repetitively even though none of the calls threw an error (as mentioned above under the `session.respond` call, like following.
//
// respond(to:images:)
// call(arguments:) Arguments(image: FoundationModels.ImageReference(attachmentLabel: "image_0"), width: 1000.0, height: 1000.0)
// call(arguments:) Arguments(image: FoundationModels.ImageReference(attachmentLabel: "image_0"), width: 1000.0, height: 1000.0)
// call(arguments:) Arguments(image: FoundationModels.ImageReference(attachmentLabel: "image_0"), width: 1000.0, height: 1000.0)
//
// @Generable
// struct StructuredResponse {
//     @Guide(description: "Output from tools if there is any")
//     var newImages: [ImageReference]
//     var textResponse: String
// }


private struct ResizeImageTool: Tool {
    // a callback to get current session transcript
    // required for resolving image reference,
    // and is NOT provided to the tool `call` directly
    let getSessionTranscript: @Sendable () -> Transcript?
    let name = "Resize"
    let description = "resize a given image"

    init(getSessionTranscript: @Sendable @escaping () -> Transcript?) {
        self.getSessionTranscript = getSessionTranscript
    }

    @Generable
    struct Arguments {
        // Accepting Image Input
        @Guide(description: "The identifier of the image to resize.")
        var image: ImageReference

        @Guide(description: "Target image width.")
        var width: Float

        @Guide(description: "Target image height.")
        var height: Float

    }

    // respond with image
    func call(arguments: Arguments) async throws -> Attachment<
        ImageAttachmentContent
    > {
        guard let transcripts = getSessionTranscript() else {
            throw FoundationModels.LanguageModelError.refusal(
                .init(
                    debugDescription:
                        "Fail to get transcriptions in the current session."
                )
            )
        }
        guard let attachment = arguments.image.resolve(in: transcripts)
        else {
            throw FoundationModels.LanguageModelError.refusal(
                .init(debugDescription: "Fail to resolve image.")
            )
        }

        guard
            let resize = attachment.ciImage.resize(
                to: .init(
                    width: CGFloat(arguments.width),
                    height: CGFloat(arguments.height)
                )
            )
        else {
            throw FoundationModels.LanguageModelError.refusal(
                .init(debugDescription: "Fail to resize image.")
            )
        }

        let resizedAttachment = Attachment(resize).label(
            "resized_\(arguments.image)_\(Date().ISO8601Format())"
        )
        return resizedAttachment
    }
}

nonisolated
    extension CIImage
{
    func resize(to targetSize: CGSize) -> CIImage? {
        let image = self
        // 1. Calculate the scale and aspect ratio
        let scaleX = targetSize.width / image.extent.width
        let scaleY = targetSize.height / image.extent.height
        let scale = min(scaleX, scaleY)  // Or use max, depending on your scaling strategy
        let aspectRatio = targetSize.width / (image.extent.width * scale)

        // 2. Create and configure the filter
        guard let resizeFilter = CIFilter(name: "CILanczosScaleTransform")
        else { return nil }
        resizeFilter.setValue(image, forKey: kCIInputImageKey)
        resizeFilter.setValue(scale, forKey: kCIInputScaleKey)
        resizeFilter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)

        // 3. Return the resized image
        return resizeFilter.outputImage
    }
}

extension Image {
    init(attachement: Transcript.ImageAttachment) {
        #if os(macOS)
            let nsImage = NSImage(
                cgImage: attachement.cgImage,
                size: .init(
                    width: CGFloat(attachement.cgImage.width),
                    height: CGFloat(attachement.cgImage.height)
                )
            )
            self = Image(nsImage: nsImage)
        #else
            let image = UIImage(
                cgImage: attachement.cgImage,
            )
            self = Image(uiImage: image)
        #endif
    }
}
