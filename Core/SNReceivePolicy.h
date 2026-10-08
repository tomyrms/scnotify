#ifndef SN_RECEIVE_POLICY_H
#define SN_RECEIVE_POLICY_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef enum { SN_RX_NONE=0, SN_RX_MESSAGE=1, SN_RX_SNAP=2, SN_RX_CONTROL=3 } SNReceiveKind;
typedef enum { SN_SOURCE_NONE=0, SN_SOURCE_LIVE=1, SN_SOURCE_SNAPSHOT=2 } SNReceiveSource;
/* Symbolic enums only. Numeric values are resolved using the host's own enum
   descriptor, or an explicit class.field mapping; never by a global guess. */
SNReceiveKind sn_receive_kind(const char *symbol);
/* Candidate hooks, not evidence that a message was received. The adapter still
   requires an actual message, its sender, conversation and stable message ID. */
SNReceiveSource sn_receive_source(const char *class_name, const char *selector);
SNReceiveKind sn_receive_hint(const char *selector);
/* Unix seconds/ms/us/ns -> seconds. NaN means invalid. */
double sn_receive_seconds(double raw);
bool sn_receive_time_valid(double seconds, double wall_now);
#ifdef __cplusplus
}
#endif
#endif
