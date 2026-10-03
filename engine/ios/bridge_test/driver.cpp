// Exercises engine/ios/katago_bridge.cpp the way the iOS app does: start the
// analysis engine in-process, wait for "ready", send a query, read the reply.
#include <cstdio>
#include <cstring>
#include <vector>
extern "C" int katago_start(int, const char**);
extern "C" void katago_send_line(const char*);
extern "C" void katago_close_input();
extern "C" int katago_read_line(char*, int);

int main(int argc, const char** argv) {
  if (argc < 3) { std::printf("usage: driver CONFIG MODEL\n"); return 2; }
  const char* args[] = {"analysis", "-config", argv[1], "-model", argv[2],
                        "-override-config", "reportAnalysisWinratesAs=BLACK"};
  if (katago_start(7, args) != 0) return 3;
  static char buf[8 << 20];
  bool sent = false, gotReply = false;
  int exitCode = -1;
  while (true) {
    int n = katago_read_line(buf, sizeof buf);
    if (n < 0) break;
    if (std::strncmp(buf, "#EXIT ", 6) == 0) { exitCode = std::atoi(buf + 6); continue; }
    if (buf[0] == '{') {
      std::printf("REPLY %.300s...\n", buf);
      if (std::strstr(buf, "\"id\":\"t1\"") && std::strstr(buf, "moveInfos")) {
        gotReply = true;
        katago_close_input();
      }
    } else if (!sent && std::strstr(buf, "ready to begin handling requests")) {
      std::printf("READY\n");
      katago_send_line("{\"id\":\"t1\",\"moves\":[[\"B\",\"E5\"]],\"rules\":\"japanese\",\"komi\":6.5,"
                       "\"boardXSize\":9,\"boardYSize\":9,\"maxVisits\":30}");
      sent = true;
    }
    std::fflush(stdout);
  }
  std::printf("EXIT %d reply=%d\n", exitCode, gotReply ? 1 : 0);
  return gotReply && exitCode == 0 ? 0 : 1;
}
