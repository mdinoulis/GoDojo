// In-process bridge for running KataGo's JSON analysis engine on iOS, where
// apps cannot start subprocesses. KataGo's stdin/stdout/stderr are redirected
// to in-memory line queues that the Dart side reads/writes through dart:ffi
// (see app/lib/ios_ffi_transport.dart).
//
// Build: compile together with KataGo's cpp/ sources (Metal backend), with
// cpp/main.cpp compiled using -Dmain=katago_cli_main so it does not clash with
// the app's own entry point. See engine/ios/README.md.

#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>
#include <vector>

#include "main.h"  // MainCmds::analysis

namespace {

class LineQueue {
 public:
  void push(std::string s) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (closed_) return;
      lines_.push_back(std::move(s));
    }
    cv_.notify_one();
  }
  // Blocks until a line is available; returns false once closed and drained.
  bool pop(std::string& out) {
    std::unique_lock<std::mutex> lock(mutex_);
    cv_.wait(lock, [&] { return !lines_.empty() || closed_; });
    if (lines_.empty()) return false;
    out = std::move(lines_.front());
    lines_.pop_front();
    return true;
  }
  void close() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      closed_ = true;
    }
    cv_.notify_all();
  }

 private:
  std::mutex mutex_;
  std::condition_variable cv_;
  std::deque<std::string> lines_;
  bool closed_ = false;
};

LineQueue toEngine;
LineQueue fromEngine;

// std::cin source: yields the lines sent by the app.
class InputBuf : public std::streambuf {
 protected:
  int_type underflow() override {
    if (gptr() < egptr()) return traits_type::to_int_type(*gptr());
    std::string line;
    if (!toEngine.pop(line)) return traits_type::eof();
    current_ = line + "\n";
    setg(&current_[0], &current_[0], &current_[0] + current_.size());
    return traits_type::to_int_type(*gptr());
  }

 private:
  std::string current_;
};

// std::cout / std::cerr sink: splits output into lines for the app.
class OutputBuf : public std::streambuf {
 public:
  explicit OutputBuf(std::string prefix) : prefix_(std::move(prefix)) {}

 protected:
  int_type overflow(int_type c) override {
    if (traits_type::eq_int_type(c, traits_type::eof())) return 0;
    std::lock_guard<std::mutex> lock(mutex_);
    put(static_cast<char>(c));
    return c;
  }
  std::streamsize xsputn(const char* s, std::streamsize n) override {
    std::lock_guard<std::mutex> lock(mutex_);
    for (std::streamsize i = 0; i < n; i++) put(s[i]);
    return n;
  }

 private:
  void put(char c) {
    if (c == '\n') {
      fromEngine.push(prefix_ + buffer_);
      buffer_.clear();
    } else {
      buffer_.push_back(c);
    }
  }
  std::string prefix_;
  std::string buffer_;
  std::mutex mutex_;
};

InputBuf inputBuf;
OutputBuf outputBuf("");
OutputBuf errorBuf("#ERR ");
std::thread engineThread;
bool started = false;

}  // namespace

extern "C" {

// Starts "katago analysis <args>" on a background thread. argv[0] should be
// "analysis". Returns 0 on success, -1 if already started.
__attribute__((visibility("default"))) int katago_start(int argc, const char** argv) {
  if (started) return -1;
  started = true;
  std::cin.rdbuf(&inputBuf);
  std::cout.rdbuf(&outputBuf);
  std::cerr.rdbuf(&errorBuf);
  std::vector<std::string> args(argv, argv + argc);
  engineThread = std::thread([args] {
    int rc = 1;
    try {
      rc = MainCmds::analysis(args);
    } catch (const std::exception& e) {
      fromEngine.push(std::string("#ERR Uncaught exception: ") + e.what());
    }
    fromEngine.push("#EXIT " + std::to_string(rc));
    fromEngine.close();
  });
  engineThread.detach();
  return 0;
}

__attribute__((visibility("default"))) void katago_send_line(const char* line) {
  toEngine.push(line);
}

// Closing the input makes KataGo finish its queued work and exit.
__attribute__((visibility("default"))) void katago_close_input() { toEngine.close(); }

// Blocks until the engine writes a line. Copies it (NUL-terminated, truncated
// to cap-1 bytes) into buf and returns its full length, or -1 once the engine
// has exited and all output was read.
__attribute__((visibility("default"))) int katago_read_line(char* buf, int cap) {
  std::string line;
  if (!fromEngine.pop(line)) return -1;
  const size_t n = std::min(line.size(), static_cast<size_t>(cap - 1));
  std::memcpy(buf, line.data(), n);
  buf[n] = '\0';
  return static_cast<int>(line.size());
}

}  // extern "C"
