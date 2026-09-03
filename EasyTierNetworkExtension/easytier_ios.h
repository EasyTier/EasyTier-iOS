#ifndef EASYTIER_IOS_H
#define EASYTIER_IOS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t init_logger(const char *path, const char *level, const char *subsystem, const char **err_msg);

int32_t clear_logger(const char **err_msg);

int32_t set_tun_fd(int32_t fd, const char **err_msg);

void free_string(const char *s);

int32_t run_network_instance(const char *cfg_str, const char **err_msg);

typedef void (*config_server_event_callback_t)(const char *event_json);

int32_t start_config_server_client(const char *url,
                                   const char *hostname,
                                   const char *machine_id,
                                   config_server_event_callback_t callback,
                                   const char **err_msg);

int32_t is_config_server_client_connected(void);

int32_t get_config_server_status(const char **json, const char **err_msg);

int32_t complete_config_server_instance_setup(uint64_t generation,
                                              bool success,
                                              const char *error);

int32_t stop_network_instance(void);

int32_t register_stop_callback(void (*callback)(void), const char **err_msg);

int32_t register_running_info_callback(void (*callback)(void), const char **err_msg);

int32_t get_running_info(const char **json, const char **err_msg);

int32_t get_latest_error_msg(const char **msg, const char **err_msg);

#ifdef __cplusplus
}
#endif

#endif
