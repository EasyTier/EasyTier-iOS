#ifndef EASYTIER_IOS_H
#define EASYTIER_IOS_H

#include <stdint.h>
#include <stddef.h>

/**
 * Initialize logger
 * level: off, error, warn. info, debug, trace
 * Returns 0 on success, -1 on failure.
 */
int init_logger(const char *path, const char *level, const char **err_msg);

/**
 * Set the tun file descriptor.
 * Returns 0 on success, -1 on failure.
 */
int set_tun_fd(int fd, const char **err_msg);

/**
 * Frees a string that was allocated by the Rust side
 */
void free_string(const char *s);

/**
 * Starts a network instance with the provided TOML configuration.
 * Returns 0 on success, -1 on failure.
 */
int run_network_instance(const char *cfg_str, const char **err_msg);

/**
 * Stop the network instance.
 */
int stop_network_instance();

/**
 * Get running instance information.
 * Returns 0 on success, -1 on failure.
 */
int get_running_info(const char **json, const char **err_msg);

#endif
