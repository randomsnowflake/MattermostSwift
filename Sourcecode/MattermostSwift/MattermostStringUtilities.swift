extension String {
    var mattermostTrimmingLeadingSlashes: String {
        String(drop(while: { $0 == "/" }))
    }

    var mattermostTrimmingTrailingSlashes: String {
        guard let lastNonSlash = lastIndex(where: { $0 != "/" }) else {
            return ""
        }
        return String(self[...lastNonSlash])
    }
}
