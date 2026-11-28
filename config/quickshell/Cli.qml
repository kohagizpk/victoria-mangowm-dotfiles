import QtQuick
import Quickshell
import Quickshell.Io

// Serial queue around scripts/victoria-cli.py (one JSON line per call).
Item {
    id: cli
    readonly property string script: Quickshell.env("HOME") + "/.config/mango/scripts/victoria-cli.py"
    property var queue: []
    property var current: null
    readonly property bool busy: current !== null

    function call(command, argument, done) {
        queue = queue.concat([{ command: command, argument: argument, done: done }])
        if (current === null) next()
    }
    function next() {
        if (current !== null || queue.length === 0) return
        current = queue[0]
        queue = queue.slice(1)
        proc.command = ["python3", "-B", script, current.command]
            .concat(current.argument === undefined ? [] : [JSON.stringify(current.argument)])
        proc.running = true
    }

    Process {
        id: proc
        // Finish on end-of-output, which also fires when the script crashes.
        stdout: StdioCollector {
            onStreamFinished: {
                let result
                try { result = JSON.parse(text) } catch (e) { result = { ok: false, error: text.trim() || "No response from victoria-cli.py" } }
                const job = cli.current
                cli.current = null
                if (job && job.done) job.done(result)
                Qt.callLater(cli.next)
            }
        }
    }
}
