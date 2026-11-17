#include "CSBridge.h"

#include <atomic>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <mutex>
#include <poll.h>
#include <streambuf>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

#include "bitboard.h"
#include "endgame.h"
#include "position.h"
#include "search.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"

namespace PSQT {
void init();
}

namespace {

/// A std::streambuf that reads and writes one file descriptor.
/// Needed because libc++ has no stdio_filebuf, and because redirecting the process's real
/// file descriptors 0/1 would break anything else that writes to stdout.
class FDStreamBuf : public std::streambuf {
public:
    explicit FDStreamBuf(int fd) : fd_(fd) { setg(buffer_, buffer_, buffer_); }

    ~FDStreamBuf() override {
        sync();
    }

protected:
    int_type overflow(int_type ch) override {
        if (ch == traits_type::eof()) return traits_type::not_eof(ch);
        char c = static_cast<char>(ch);
        if (write_bytes(&c, 1) != 1) return traits_type::eof();
        return ch;
    }

    std::streamsize xsputn(const char *s, std::streamsize n) override {
        return write_bytes(s, static_cast<size_t>(n));
    }

    int sync() override { return 0; }

    int_type underflow() override {
        if (gptr() < egptr()) return traits_type::to_int_type(*gptr());
        ssize_t n = ::read(fd_, buffer_, kBufferSize);
        if (n <= 0) return traits_type::eof();
        setg(buffer_, buffer_, buffer_ + n);
        return traits_type::to_int_type(*gptr());
    }

private:
    std::streamsize write_bytes(const char *s, size_t n) {
        size_t sent = 0;
        while (sent < n) {
            ssize_t w = ::write(fd_, s + sent, n - sent);
            if (w < 0) {
                if (errno == EINTR) continue;
                return static_cast<std::streamsize>(sent);
            }
            sent += static_cast<size_t>(w);
        }
        return static_cast<std::streamsize>(sent);
    }

    static constexpr size_t kBufferSize = 4096;
    int fd_;
    char buffer_[kBufferSize];
};

struct Engine {
    int in_fd = -1;    ///< written by us, read by cin
    int out_fd = -1;   ///< written by cout, read by us
    FDStreamBuf *in_buf = nullptr;
    FDStreamBuf *out_buf = nullptr;
    std::thread thread;
    std::atomic<bool> running{false};
    std::mutex send_lock;
    std::string pending;  ///< bytes of a line not yet terminated by \n
};

Engine &engine() {
    static Engine instance;
    return instance;
}

/// The initialisation Stockfish's own main() performs before UCI::loop.
///
/// Skipping it left `Threads` empty, and ThreadPool::main() calls `threads.front()` on the
/// first search -- an immediate abort. main.cpp is not compiled into the app, so its startup
/// sequence is reproduced here, in the same order.
void engine_init() {
    static std::once_flag once;
    std::call_once(once, [] {
        UCI::init(Options);
        PSQT::init();
        Bitboards::init();
        Position::init();
        Bitbases::init();
        Endgames::init();
        Threads.set(Options["Threads"]);
        Search::clear();
    });
}

void loop_thread() {
    engine_init();
    // argc must be exactly 1: Stockfish only enters its interactive read loop when argc == 1,
    // and with 0 it returns immediately without ever reading stdin.
    static char engine_name[] = "stockfish";
    static char* engine_argv[] = {engine_name, nullptr};
    UCI::loop(1, engine_argv);
}

}  // namespace

extern "C" int cs_engine_start(void) {
    Engine &e = engine();

    std::lock_guard<std::mutex> guard(e.send_lock);
    if (e.running.load()) return 0;

    // Two socketpairs, one per direction. A single pair reused for both directions deadlocks
    // in a subtle way: cin would end up reading the engine's own output and consuming it.
    int to_engine[2];
    int from_engine[2];
    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, to_engine) != 0) return -1;
    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, from_engine) != 0) return -1;

    e.in_fd = to_engine[0];      ///< host writes here
    e.out_fd = from_engine[0];   ///< host reads here

    e.in_buf = new FDStreamBuf(to_engine[1]);     ///< the engine's stdin
    e.out_buf = new FDStreamBuf(from_engine[1]);  ///< the engine's stdout
    std::cin.rdbuf(e.in_buf);
    std::cout.rdbuf(e.out_buf);

    e.running.store(true);
    e.thread = std::thread(loop_thread);
    e.thread.detach();
    return 0;
}

extern "C" int cs_engine_send(const char *command) {
    Engine &e = engine();
    if (!e.running.load() || command == nullptr) return -1;

    std::lock_guard<std::mutex> guard(e.send_lock);
    std::string line(command);
    line.push_back('\n');
    ssize_t written = ::write(e.in_fd, line.data(), line.size());
    return written == static_cast<ssize_t>(line.size()) ? 0 : -1;
}

extern "C" int cs_engine_read_line(char *buffer, int capacity, int timeout_ms) {
    Engine &e = engine();
    if (!e.running.load() || buffer == nullptr || capacity <= 1) return -1;

    for (;;) {
        size_t newline = e.pending.find('\n');
        if (newline != std::string::npos) {
            std::string line = e.pending.substr(0, newline);
            e.pending.erase(0, newline + 1);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            std::strncpy(buffer, line.c_str(), static_cast<size_t>(capacity - 1));
            buffer[capacity - 1] = '\0';
            return 1;
        }

        struct pollfd pfd = {e.out_fd, POLLIN, 0};
        int ready = ::poll(&pfd, 1, timeout_ms);
        if (ready == 0) return 0;
        if (ready < 0) {
            if (errno == EINTR) continue;
            return -1;
        }

        char chunk[1024];
        ssize_t n = ::read(e.out_fd, chunk, sizeof(chunk));
        if (n <= 0) return -1;
        e.pending.append(chunk, static_cast<size_t>(n));
    }
}

extern "C" int cs_engine_is_running(void) {
    return engine().running.load() ? 1 : 0;
}
