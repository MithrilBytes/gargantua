import Foundation

/// Every failure leaves through here: one plain sentence on stderr and a
/// nonzero exit code. 2 is an operational error, 64 is a usage error.
enum Exit {
    static func fail(_ sentence: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((sentence + "\n").utf8))
        exit(code)
    }

    static func operational(_ sentence: String) -> Never {
        fail(sentence, code: 2)
    }

    static func usage(_ sentence: String) -> Never {
        fail(sentence, code: 64)
    }
}

/// Stdout that flushes immediately, so progress lines show up in a pipe.
enum Console {
    static func line(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}
