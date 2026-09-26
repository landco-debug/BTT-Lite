import Foundation
import JavaScriptCore

private struct TransformRequest: Codable {
    var script: String
    var text: String
}

private struct TransformResponse: Codable {
    var ok: Bool
    var result: String?
    var error: String?
}

private func writeResponse(_ response: TransformResponse) -> Never {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(response) {
        FileHandle.standardOutput.write(data)
    }
    exit(response.ok ? 0 : 1)
}

private func jsonString(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object),
          let string = String(data: data, encoding: .utf8) else { return "{}" }
    return string
}

private func nativeFetch(_ rawURL: String) -> String {
    var output: [String: Any] = ["status": 0, "body": "", "error": "Invalid URL"]
    guard let url = URL(string: rawURL) else {
        return jsonString(output)
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    var body = ""
    var status = 0
    var errorText: String?

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let http = response as? HTTPURLResponse { status = http.statusCode }
        if let data { body = String(data: data, encoding: .utf8) ?? "" }
        if let error { errorText = error.localizedDescription }
        semaphore.signal()
    }.resume()

    if semaphore.wait(timeout: .now() + 22) == .timedOut {
        errorText = "Request timed out"
    }
    output = ["status": status, "body": body]
    if let errorText { output["error"] = errorText }
    return jsonString(output)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let request = try? JSONDecoder().decode(TransformRequest.self, from: input) else {
    writeResponse(TransformResponse(ok: false, result: nil, error: "Invalid helper request"))
}

guard let context = JSContext() else {
    writeResponse(TransformResponse(ok: false, result: nil, error: "Could not create JavaScript context"))
}

var exceptionText: String?
context.exceptionHandler = { _, exception in
    exceptionText = exception?.toString() ?? "JavaScript exception"
}

let fetchBlock: @convention(block) (String) -> String = { rawURL in
    nativeFetch(rawURL)
}
context.setObject(fetchBlock, forKeyedSubscript: "__bttNativeFetch" as NSString)
context.setObject(request.script, forKeyedSubscript: "__bttSource" as NSString)
context.setObject(request.text, forKeyedSubscript: "__bttInput" as NSString)

context.evaluateScript(#"""
globalThis.fetch = async function(url, options) {
    const native = JSON.parse(__bttNativeFetch(String(url)));
    return {
        ok: native.status >= 200 && native.status < 300,
        status: native.status,
        json: async function() { return JSON.parse(native.body); },
        text: async function() { return native.body; }
    };
};
var __bttDone = false;
var __bttResult = null;
var __bttError = null;
try {
    var __bttFunction = eval("(" + __bttSource + ")");
    Promise.resolve(__bttFunction(__bttInput)).then(
        function(value) {
            __bttResult = value == null ? "" : String(value);
            __bttDone = true;
        },
        function(error) {
            __bttError = String(error);
            __bttDone = true;
        }
    );
} catch (error) {
    __bttError = String(error);
    __bttDone = true;
}
"""#)

let deadline = Date().addingTimeInterval(30)
while context.objectForKeyedSubscript("__bttDone")?.toBool() != true && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
}

if let exceptionText {
    writeResponse(TransformResponse(ok: false, result: nil, error: exceptionText))
}
if context.objectForKeyedSubscript("__bttDone")?.toBool() != true {
    writeResponse(TransformResponse(ok: false, result: nil, error: "JavaScript transform timed out"))
}
if let error = context.objectForKeyedSubscript("__bttError"), !error.isNull, !error.isUndefined {
    writeResponse(TransformResponse(ok: false, result: nil, error: error.toString()))
}
let result = context.objectForKeyedSubscript("__bttResult")?.toString() ?? ""
writeResponse(TransformResponse(ok: true, result: result, error: nil))
