import Foundation

// MARK: - Message attachments (interactive messages)

/// A Slack-style message attachment from a post's `props.attachments`.
///
/// Integrations and bots render cards this way: a colour bar, pretext, author,
/// title, markdown text, fields, images, a footer and interactive `actions`.
/// Every field is optional; unknown or malformed values decode as `nil` instead
/// of failing the post. See
/// https://developers.mattermost.com/integrate/reference/message-attachments/
public struct MattermostMessageAttachment: Equatable, Hashable, Sendable {
    public let fallback: String?
    /// A hex colour (`#2D9CDB`) or one of `good`, `warning`, `danger`.
    public let color: String?
    public let pretext: String?
    public let authorName: String?
    public let authorLink: String?
    public let authorIcon: String?
    public let title: String?
    public let titleLink: String?
    public let text: String?
    public let fields: [Field]
    public let imageURL: String?
    public let thumbURL: String?
    public let footer: String?
    public let footerIcon: String?
    public let actions: [MattermostPostAction]

    public struct Field: Equatable, Hashable, Sendable {
        public let title: String?
        /// Slack allows numbers here; they arrive as their string form.
        public let value: String?
        /// Short fields sit side by side.
        public let isShort: Bool

        public init(title: String?, value: String?, isShort: Bool) {
            self.title = title
            self.value = value
            self.isShort = isShort
        }
    }

    public init(
        fallback: String? = nil,
        color: String? = nil,
        pretext: String? = nil,
        authorName: String? = nil,
        authorLink: String? = nil,
        authorIcon: String? = nil,
        title: String? = nil,
        titleLink: String? = nil,
        text: String? = nil,
        fields: [Field] = [],
        imageURL: String? = nil,
        thumbURL: String? = nil,
        footer: String? = nil,
        footerIcon: String? = nil,
        actions: [MattermostPostAction] = []
    ) {
        self.fallback = fallback
        self.color = color
        self.pretext = pretext
        self.authorName = authorName
        self.authorLink = authorLink
        self.authorIcon = authorIcon
        self.title = title
        self.titleLink = titleLink
        self.text = text
        self.fields = fields
        self.imageURL = imageURL
        self.thumbURL = thumbURL
        self.footer = footer
        self.footerIcon = footerIcon
        self.actions = actions
    }

    /// Reads one attachment object; `nil` when the value is not a JSON object.
    public init?(json: MattermostJSONValue) {
        guard case .object(let object) = json else { return nil }
        self.init(
            fallback: object["fallback"]?.displayString,
            color: object["color"]?.displayString,
            pretext: object["pretext"]?.displayString,
            authorName: object["author_name"]?.displayString,
            authorLink: object["author_link"]?.displayString,
            authorIcon: object["author_icon"]?.displayString,
            title: object["title"]?.displayString,
            titleLink: object["title_link"]?.displayString,
            text: object["text"]?.displayString,
            fields: object["fields"]?.arrayValue?.compactMap { field in
                guard case .object(let field) = field else { return nil }
                return Field(
                    title: field["title"]?.displayString,
                    value: field["value"]?.displayString,
                    isShort: field["short"]?.boolValue ?? false
                )
            } ?? [],
            imageURL: object["image_url"]?.displayString,
            thumbURL: object["thumb_url"]?.displayString,
            footer: object["footer"]?.displayString,
            footerIcon: object["footer_icon"]?.displayString,
            actions: object["actions"]?.arrayValue?.compactMap(MattermostPostAction.init(json:)) ?? []
        )
    }
}

/// A button or select menu on a message attachment.
///
/// The server strips the integration URL before sending posts to clients.
/// Trigger it with ``MattermostClient/doPostAction(postID:actionID:selectedOption:cookie:)``.
public struct MattermostPostAction: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case button
        case select
        case other(String)
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// `default`, `primary`, `success`, `good`, `warning`, `danger` or a hex colour.
    public let style: String?
    /// `users` or `channels` for dynamic select menus; `nil` for static options.
    public let dataSource: String?
    public let options: [MattermostSelectOption]
    public let defaultOption: String?
    public let isDisabled: Bool
    /// Present on ephemeral posts, which the server cannot look up; send it back unchanged.
    public let cookie: String?

    public init(
        id: String,
        name: String,
        kind: Kind = .button,
        style: String? = nil,
        dataSource: String? = nil,
        options: [MattermostSelectOption] = [],
        defaultOption: String? = nil,
        isDisabled: Bool = false,
        cookie: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.style = style
        self.dataSource = dataSource
        self.options = options
        self.defaultOption = defaultOption
        self.isDisabled = isDisabled
        self.cookie = cookie
    }

    /// Reads one action object; `nil` without an id, which the server needs to run it.
    public init?(json: MattermostJSONValue) {
        guard case .object(let object) = json,
              let id = object["id"]?.displayString, !id.isEmpty else { return nil }
        let type = object["type"]?.displayString ?? "button"
        let kind: Kind = switch type {
        case "button", "": .button
        case "select": .select
        default: .other(type)
        }
        self.init(
            id: id,
            name: object["name"]?.displayString ?? "",
            kind: kind,
            style: object["style"]?.displayString,
            dataSource: object["data_source"]?.displayString?.mattermostNilIfEmpty,
            options: MattermostSelectOption.options(from: object["options"]),
            defaultOption: object["default_option"]?.displayString?.mattermostNilIfEmpty,
            isDisabled: object["disabled"]?.boolValue ?? false,
            cookie: object["cookie"]?.displayString?.mattermostNilIfEmpty
        )
    }
}

/// One option of a static select menu (message attachment or dialog).
public struct MattermostSelectOption: Equatable, Hashable, Sendable {
    public let text: String
    public let value: String

    public init(text: String, value: String) {
        self.text = text
        self.value = value
    }

    static func options(from json: MattermostJSONValue?) -> [MattermostSelectOption] {
        json?.arrayValue?.compactMap { option in
            guard case .object(let option) = option,
                  let value = option["value"]?.displayString else { return nil }
            return MattermostSelectOption(text: option["text"]?.displayString ?? value, value: value)
        } ?? []
    }
}

extension MattermostPost {
    /// Typed `props.attachments`; empty when the post has none.
    public var messageAttachments: [MattermostMessageAttachment] {
        props?["attachments"]?.arrayValue?.compactMap(MattermostMessageAttachment.init(json:)) ?? []
    }
}

/// Response of `POST /posts/{post_id}/actions/{action_id}`.
public struct MattermostPostActionResponse: Codable, Equatable, Sendable {
    public let status: String?
    /// Set when the integration may open an interactive dialog.
    public let triggerID: String?
    /// A URL the client should open (a permalink or an external page).
    public let gotoLocation: String?

    public init(status: String? = nil, triggerID: String? = nil, gotoLocation: String? = nil) {
        self.status = status
        self.triggerID = triggerID
        self.gotoLocation = gotoLocation
    }

    enum CodingKeys: String, CodingKey {
        case status
        case triggerID = "triggerId"
        case gotoLocation
    }
}

struct MattermostPostActionRequest: Encodable, Sendable {
    let selectedOption: String?
    let cookie: String?
}

// MARK: - Interactive dialogs

/// The `open_dialog` WebSocket payload: a dialog an integration asks this user to fill in.
/// See https://developers.mattermost.com/integrate/plugins/interactive-dialogs/
public struct MattermostOpenDialogRequest: Equatable, Sendable {
    public let triggerID: String
    /// The integration URL the submission goes to; pass it back in ``MattermostDialogSubmission``.
    public let url: String
    public let dialog: MattermostDialog

    public init(triggerID: String, url: String, dialog: MattermostDialog) {
        self.triggerID = triggerID
        self.url = url
        self.dialog = dialog
    }

    public init?(json: MattermostJSONValue) {
        guard case .object(let object) = json,
              let url = object["url"]?.displayString,
              let dialog = object["dialog"].flatMap(MattermostDialog.init(json:)) else { return nil }
        self.init(triggerID: object["trigger_id"]?.displayString ?? "", url: url, dialog: dialog)
    }
}

public struct MattermostDialog: Equatable, Sendable {
    public let callbackID: String
    public let title: String
    public let introductionText: String?
    public let iconURL: String?
    public let elements: [MattermostDialogElement]
    public let submitLabel: String?
    public let notifyOnCancel: Bool
    /// Opaque integration state; send it back unchanged.
    public let state: String

    public init(
        callbackID: String,
        title: String,
        introductionText: String? = nil,
        iconURL: String? = nil,
        elements: [MattermostDialogElement] = [],
        submitLabel: String? = nil,
        notifyOnCancel: Bool = false,
        state: String = ""
    ) {
        self.callbackID = callbackID
        self.title = title
        self.introductionText = introductionText
        self.iconURL = iconURL
        self.elements = elements
        self.submitLabel = submitLabel
        self.notifyOnCancel = notifyOnCancel
        self.state = state
    }

    public init?(json: MattermostJSONValue) {
        guard case .object(let object) = json else { return nil }
        self.init(
            callbackID: object["callback_id"]?.displayString ?? "",
            title: object["title"]?.displayString ?? "",
            introductionText: object["introduction_text"]?.displayString?.mattermostNilIfEmpty,
            iconURL: object["icon_url"]?.displayString?.mattermostNilIfEmpty,
            elements: object["elements"]?.arrayValue?.compactMap(MattermostDialogElement.init(json:)) ?? [],
            submitLabel: object["submit_label"]?.displayString?.mattermostNilIfEmpty,
            notifyOnCancel: object["notify_on_cancel"]?.boolValue ?? false,
            state: object["state"]?.displayString ?? ""
        )
    }
}

public struct MattermostDialogElement: Equatable, Sendable {
    public let name: String
    public let displayName: String
    /// `text`, `textarea`, `select`, `bool` or `radio` (newer servers add more).
    public let type: String
    /// For `text`: `email`, `number`, `password`, `tel`, `url` or `text`.
    public let subtype: String?
    public let defaultValue: String?
    public let placeholder: String?
    public let helpText: String?
    public let isOptional: Bool
    public let minLength: Int?
    public let maxLength: Int?
    public let dataSource: String?
    public let options: [MattermostSelectOption]

    public init(
        name: String,
        displayName: String,
        type: String,
        subtype: String? = nil,
        defaultValue: String? = nil,
        placeholder: String? = nil,
        helpText: String? = nil,
        isOptional: Bool = false,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        dataSource: String? = nil,
        options: [MattermostSelectOption] = []
    ) {
        self.name = name
        self.displayName = displayName
        self.type = type
        self.subtype = subtype
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.helpText = helpText
        self.isOptional = isOptional
        self.minLength = minLength
        self.maxLength = maxLength
        self.dataSource = dataSource
        self.options = options
    }

    public init?(json: MattermostJSONValue) {
        guard case .object(let object) = json,
              let name = object["name"]?.displayString, !name.isEmpty else { return nil }
        self.init(
            name: name,
            displayName: object["display_name"]?.displayString ?? name,
            type: object["type"]?.displayString ?? "text",
            subtype: object["subtype"]?.displayString?.mattermostNilIfEmpty,
            defaultValue: object["default"]?.displayString?.mattermostNilIfEmpty,
            placeholder: object["placeholder"]?.displayString?.mattermostNilIfEmpty,
            helpText: object["help_text"]?.displayString?.mattermostNilIfEmpty,
            isOptional: object["optional"]?.boolValue ?? false,
            minLength: object["min_length"]?.int64Value.map { Int(clamping: $0) }.flatMap { $0 > 0 ? $0 : nil },
            maxLength: object["max_length"]?.int64Value.map { Int(clamping: $0) }.flatMap { $0 > 0 ? $0 : nil },
            dataSource: object["data_source"]?.displayString?.mattermostNilIfEmpty,
            options: MattermostSelectOption.options(from: object["options"])
        )
    }
}

/// Body of `POST /actions/dialogs/submit`.
public struct MattermostDialogSubmission: Encodable, Equatable, Sendable {
    public let url: String
    public let callbackID: String
    public let state: String
    public let userID: String
    public let channelID: String
    public let teamID: String
    /// Element name -> value: strings for text/select/radio, `.bool` for `bool`
    /// elements, numbers for `number` text fields.
    public let submission: [String: MattermostJSONValue]
    public let cancelled: Bool

    public init(
        url: String,
        callbackID: String,
        state: String,
        userID: String,
        channelID: String,
        teamID: String,
        submission: [String: MattermostJSONValue],
        cancelled: Bool = false
    ) {
        self.url = url
        self.callbackID = callbackID
        self.state = state
        self.userID = userID
        self.channelID = channelID
        self.teamID = teamID
        self.submission = submission
        self.cancelled = cancelled
    }

    enum CodingKeys: String, CodingKey {
        case url
        case callbackID = "callback_id"
        case state
        case userID = "user_id"
        case channelID = "channel_id"
        case teamID = "team_id"
        case submission
        case cancelled
    }
}

/// Integration answer to a dialog submission. Both empty means accepted.
public struct MattermostDialogSubmissionResponse: Decodable, Equatable, Sendable {
    /// A message for the whole form.
    public let error: String?
    /// Element name -> message.
    public let errors: [String: String]

    public init(error: String? = nil, errors: [String: String] = [:]) {
        self.error = error
        self.errors = errors
    }

    public var isAccepted: Bool {
        (error ?? "").isEmpty && errors.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        errors = try container.decodeIfPresent([String: String].self, forKey: .errors) ?? [:]
    }
}

// MARK: - Helpers

extension MattermostJSONValue {
    /// Array elements, or `nil` for any other value.
    public var arrayValue: [MattermostJSONValue]? {
        if case .array(let values) = self {
            return values
        }
        return nil
    }

    /// Strings as-is, numbers and booleans in their JSON text form; `nil` otherwise.
    public var displayString: String? {
        switch self {
        case .string(let value):
            value
        case .integer(let value):
            String(value)
        case .unsignedInteger(let value):
            String(value)
        case .number(let value):
            value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .bool(let value):
            String(value)
        case .object, .array, .null:
            nil
        }
    }
}

private extension String {
    var mattermostNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
