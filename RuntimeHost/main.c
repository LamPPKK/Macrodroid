#include <errno.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *qos_name(qos_class_t qos_class) {
    switch (qos_class) {
        case QOS_CLASS_USER_INTERACTIVE: return "user_interactive";
        case QOS_CLASS_USER_INITIATED: return "user_initiated";
        case QOS_CLASS_DEFAULT: return "default";
        case QOS_CLASS_UTILITY: return "utility";
        case QOS_CLASS_BACKGROUND: return "background";
        default: return "unspecified";
    }
}

int main(int argc, char *argv[]) {
    const char *stdout_path = getenv("TFT_HOST_STDOUT");
    const char *stderr_path = getenv("TFT_HOST_STDERR");
    if (stdout_path != NULL && stdout_path[0] != '\0') {
        (void)freopen(stdout_path, "a", stdout);
    }
    if (stderr_path != NULL && stderr_path[0] != '\0') {
        (void)freopen(stderr_path, "a", stderr);
    }

    const char *qos_request = getenv("TFT_HOST_LATENCY_QOS");
    const int latency_qos_requested = qos_request != NULL && strcmp(qos_request, "user_interactive") == 0;
    const int qos_result = latency_qos_requested
        ? pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        : 0;
    qos_class_t effective_qos = QOS_CLASS_UNSPECIFIED;
    int relative_priority = 0;
    const int qos_read_result = pthread_get_qos_class_np(
        pthread_self(),
        &effective_qos,
        &relative_priority
    );
    if (qos_read_result != 0) {
        effective_qos = QOS_CLASS_UNSPECIFIED;
        relative_priority = 0;
    }
    dprintf(STDOUT_FILENO, "TFTMAC_HOST_QOS_REQUESTED=%s\n",
        latency_qos_requested ? "user_interactive" : "default");
    dprintf(STDOUT_FILENO, "TFTMAC_HOST_QOS_SET_RESULT=%d\n", qos_result);
    dprintf(STDOUT_FILENO, "TFTMAC_HOST_QOS_EFFECTIVE=%s\n", qos_name(effective_qos));
    dprintf(STDOUT_FILENO, "TFTMAC_HOST_QOS_RELATIVE_PRIORITY=%d\n", relative_priority);

    const char *emulator = getenv("TFT_EMULATOR");
    if (emulator == NULL || emulator[0] == '\0' || access(emulator, X_OK) != 0) {
        fputs("TFTMAC Emulator Host could not find the Android Emulator executable.\n", stderr);
        return EXIT_FAILURE;
    }

    argv[0] = (char *)emulator;
    execv(emulator, argv);
    fprintf(stderr, "TFTMAC Emulator Host could not start Android Emulator: %s\n", strerror(errno));
    return EXIT_FAILURE;
}
