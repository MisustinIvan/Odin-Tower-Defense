package main

import "core:fmt"
import "core:time"

LOG_LEVEL :: enum {
    INFO,
    WARN,
    ERROR,
}

log :: proc(lvl : LOG_LEVEL, msg : string) {
    prefix := ""
    switch lvl {
    case .INFO: prefix = "INFO"
    case .WARN: prefix = "WARN"
    case .ERROR: prefix = "ERORR"
    }

    timestamp, _ := time.time_to_datetime(time.now())
    fmt.printf("[%s] :: %02d:%02d:%02d :: %s\n", prefix, timestamp.hour, timestamp.minute, timestamp.second, msg)
}
