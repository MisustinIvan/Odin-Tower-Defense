package main

import "core:fmt"
import "core:time"

LOG_LEVEL :: enum {
    INFO,
    WARN,
    ERROR,
    PANIC,
}

log :: proc(lvl : LOG_LEVEL, msg : string, args : ..any) {
    prefix := ""
    switch lvl {
    case .INFO: prefix = "INFO"
    case .WARN: prefix = "WARN"
    case .ERROR: prefix = "ERORR"
    case .PANIC: prefix = "PANIC"
    }

    timestamp, _ := time.time_to_datetime(time.now())
    msg_str := ""
    if len(args) == 0 {
        msg_str = fmt.aprintf("[%s] :: %02d:%02d:%02d :: %s\n", prefix, timestamp.hour, timestamp.minute, timestamp.second, msg)
    } else {
        msg_str = fmt.aprintf("[%s] :: %02d:%02d:%02d :: %s\n", prefix, timestamp.hour, timestamp.minute, timestamp.second, fmt.aprintf(msg, ..args))
    }

    if lvl == LOG_LEVEL.PANIC {
        panic(msg_str)
    }

    fmt.print(msg_str)
}
