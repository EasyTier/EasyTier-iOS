use std::{
    ffi::{c_char, c_int, CStr, CString},
    fs::File,
    io::{self, Seek, SeekFrom, Write},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use easytier::{
    common::{
        config::{ConfigFileControl, ConfigLoader, TomlConfigLoader},
        global_ctx::GlobalCtxEvent,
        MachineIdOptions,
    },
    instance_manager::NetworkInstanceManager,
    tunnel::TunnelScheme,
    web_client::{run_web_client, WebClient, WebClientHooks},
};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::{runtime::Runtime, sync::oneshot};
use tracing_oslog::OsLogger;
use tracing_subscriber::layer::SubscriberExt as _;
use uuid::Uuid;

type SharedLogFile = Arc<Mutex<File>>;
type VoidCallback = Option<extern "C" fn()>;
type ConfigServerCallback = Option<extern "C" fn(*const c_char)>;

struct CoreContext {
    runtime: Runtime,
    manager: Arc<NetworkInstanceManager>,
}

impl CoreContext {
    fn new() -> Self {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("EasyTier runtime");
        let manager = Arc::new(NetworkInstanceManager::new());
        Self { runtime, manager }
    }
}

struct ManagedWebClient {
    client: WebClient,
    hooks: Arc<AppleWebHooks>,
}

enum RunMode {
    Idle,
    Local(Uuid),
    Web(ManagedWebClient),
}

struct PendingSetup {
    generation: u64,
    instance_id: Uuid,
    sender: oneshot::Sender<Result<(), String>>,
}

#[derive(Clone)]
struct InstanceMetadata {
    instance_id: Uuid,
    instance_name: String,
    network_name: String,
    generation: u64,
}

struct AppleWebHooks {
    manager: Arc<NetworkInstanceManager>,
    callback: ConfigServerCallback,
    active: Mutex<Option<InstanceMetadata>>,
    pending: Mutex<Option<PendingSetup>>,
    generation: AtomicU64,
    stopping: AtomicBool,
    last_error: Mutex<Option<String>>,
}

impl AppleWebHooks {
    fn new(manager: Arc<NetworkInstanceManager>, callback: ConfigServerCallback) -> Self {
        Self {
            manager,
            callback,
            active: Mutex::new(None),
            pending: Mutex::new(None),
            generation: AtomicU64::new(0),
            stopping: AtomicBool::new(false),
            last_error: Mutex::new(None),
        }
    }

    fn current_id(&self) -> Option<Uuid> {
        self.active
            .lock()
            .ok()
            .and_then(|value| value.as_ref().map(|item| item.instance_id))
            .or_else(|| {
                self.pending
                    .lock()
                    .ok()
                    .and_then(|value| value.as_ref().map(|item| item.instance_id))
            })
    }

    fn emit(&self, event: &str, metadata: &InstanceMetadata) -> Result<(), String> {
        if self.stopping.load(Ordering::Acquire) {
            return Ok(());
        }
        let Some(callback) = self.callback else {
            return Ok(());
        };
        let json = serde_json::json!({
            "event": event,
            "instance_id": metadata.instance_id,
            "instance_name": metadata.instance_name,
            "network_name": metadata.network_name,
            "generation": metadata.generation,
        });
        let json = CString::new(json.to_string()).map_err(|error| error.to_string())?;
        callback(json.as_ptr());
        Ok(())
    }

    fn fail_pending(&self, message: String) {
        if let Ok(mut pending) = self.pending.lock() {
            if let Some(pending) = pending.take() {
                let _ = pending.sender.send(Err(message));
            }
        }
    }

    fn stop(&self) -> Vec<Uuid> {
        self.stopping.store(true, Ordering::Release);
        self.fail_pending("config server client stopped".to_string());
        self.active
            .lock()
            .ok()
            .and_then(|mut value| value.take())
            .map(|item| vec![item.instance_id])
            .unwrap_or_default()
    }

    fn complete_setup(&self, generation: u64, result: Result<(), String>) -> Result<(), String> {
        let mut guard = self.pending.lock().map_err(|error| error.to_string())?;
        let Some(pending) = guard.as_ref() else {
            return Err("no pending config server instance setup".to_string());
        };
        if pending.generation != generation {
            return Err(format!(
                "stale generation {generation}; current generation is {}",
                pending.generation
            ));
        }
        let pending = guard.take().expect("pending setup checked above");
        drop(guard);
        pending
            .sender
            .send(result)
            .map_err(|_| "instance setup waiter is gone".to_string())
    }

    fn metadata(&self, id: Uuid, generation: u64) -> Result<InstanceMetadata, String> {
        Ok(InstanceMetadata {
            instance_id: id,
            instance_name: self
                .manager
                .get_instance_name(&id)
                .ok_or_else(|| format!("instance {id} not found"))?,
            network_name: self
                .manager
                .get_network_name(&id)
                .ok_or_else(|| format!("network for instance {id} not found"))?,
            generation,
        })
    }
}

#[async_trait::async_trait]
impl WebClientHooks for AppleWebHooks {
    async fn pre_run_network_instance(&self, config: &TomlConfigLoader) -> Result<(), String> {
        if self.stopping.load(Ordering::Acquire) {
            return Err("config server client is stopping".to_string());
        }
        if let Some(current) = self.current_id() {
            if current != config.get_id() {
                return Err(format!(
                    "Apple client supports one Web instance; instance {current} is already active"
                ));
            }
        }
        Ok(())
    }

    async fn post_run_network_instance(&self, id: &Uuid) -> Result<(), String> {
        if self.stopping.load(Ordering::Acquire) {
            return Err("config server client is stopping".to_string());
        }
        let generation = self.generation.fetch_add(1, Ordering::AcqRel) + 1;
        let metadata = self.metadata(*id, generation)?;
        let (sender, receiver) = oneshot::channel();
        {
            let mut pending = self.pending.lock().map_err(|error| error.to_string())?;
            if pending.is_some() {
                return Err("another instance setup is pending".to_string());
            }
            *pending = Some(PendingSetup {
                generation,
                instance_id: *id,
                sender,
            });
        }
        *self.active.lock().map_err(|error| error.to_string())? = Some(metadata.clone());
        spawn_instance_event_forwarder(*id, false);
        if let Err(error) = self.emit("run", &metadata) {
            self.fail_pending(error.clone());
            return Err(error);
        }
        let setup = match tokio::time::timeout(Duration::from_secs(20), receiver).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err("instance setup acknowledgement was cancelled".to_string()),
            Err(_) => {
                self.fail_pending("instance setup timed out".to_string());
                Err("instance setup timed out".to_string())
            }
        };
        match setup {
            Ok(()) => {
                *self.last_error.lock().map_err(|error| error.to_string())? = None;
                Ok(())
            }
            Err(error) => {
                *self
                    .last_error
                    .lock()
                    .map_err(|lock_error| lock_error.to_string())? = Some(error.clone());
                Err(error)
            }
        }
    }

    async fn post_remove_network_instances(&self, ids: &[Uuid]) -> Result<(), String> {
        let removed = {
            let mut active = self.active.lock().map_err(|error| error.to_string())?;
            if active
                .as_ref()
                .is_some_and(|item| ids.contains(&item.instance_id))
            {
                active.take()
            } else {
                None
            }
        };
        if let Some(mut metadata) = removed {
            metadata.generation = self.generation.fetch_add(1, Ordering::AcqRel) + 1;
            self.emit("delete", &metadata)?;
        }
        Ok(())
    }
}

static CONTEXT: Lazy<CoreContext> = Lazy::new(CoreContext::new);
static MODE: Lazy<Mutex<RunMode>> = Lazy::new(|| Mutex::new(RunMode::Idle));
static LOGGER_FILE: Lazy<Mutex<Option<SharedLogFile>>> = Lazy::new(|| Mutex::new(None));
static STOP_CALLBACK: Lazy<Mutex<VoidCallback>> = Lazy::new(|| Mutex::new(None));
static RUNNING_INFO_CALLBACK: Lazy<Mutex<VoidCallback>> = Lazy::new(|| Mutex::new(None));

#[derive(Clone)]
struct SharedLogWriter {
    file: SharedLogFile,
}
struct SharedLogWriteGuard {
    file: SharedLogFile,
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for SharedLogWriter {
    type Writer = SharedLogWriteGuard;
    fn make_writer(&'a self) -> Self::Writer {
        SharedLogWriteGuard {
            file: self.file.clone(),
        }
    }
}

impl Write for SharedLogWriteGuard {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.file.lock().map_err(lock_io_error)?.write(buf)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.file.lock().map_err(lock_io_error)?.flush()
    }
}

fn lock_io_error<T>(error: std::sync::PoisonError<T>) -> io::Error {
    io::Error::new(io::ErrorKind::Other, error.to_string())
}

fn set_error(out: *mut *const c_char, message: impl ToString) {
    if out.is_null() {
        return;
    }
    if let Ok(message) = CString::new(message.to_string()) {
        unsafe {
            *out = message.into_raw();
        }
    }
}

fn ffi_result(result: Result<(), String>, err_msg: *mut *const c_char) -> c_int {
    match result {
        Ok(()) => 0,
        Err(error) => {
            set_error(err_msg, error);
            -1
        }
    }
}

fn active_instance_id() -> Result<Uuid, String> {
    let mode = MODE.lock().map_err(|error| error.to_string())?;
    match &*mode {
        RunMode::Local(id) => Ok(*id),
        RunMode::Web(managed) => managed
            .hooks
            .current_id()
            .ok_or_else(|| "no running instance".to_string()),
        RunMode::Idle => Err("no running instance".to_string()),
    }
}

fn normalize_config_server_endpoint(input: &str) -> Result<String, String> {
    let input = input.trim();
    if input.is_empty() {
        return Err("config server token is empty".to_string());
    }
    let endpoint = if input.contains("://") {
        input.to_string()
    } else {
        if input.contains('/') || input.chars().any(char::is_whitespace) {
            return Err("invalid config server token".to_string());
        }
        format!("udp://config-server.easytier.cn:22020/{input}")
    };
    let url = url::Url::parse(&endpoint).map_err(|error| error.to_string())?;
    TunnelScheme::try_from(&url)
        .map_err(|_| format!("unsupported config server scheme: {}", url.scheme()))?;
    if url
        .path_segments()
        .and_then(|mut parts| parts.next_back())
        .unwrap_or_default()
        .is_empty()
    {
        return Err("config server token is empty".to_string());
    }
    Ok(endpoint)
}

// Read the live config through the API exposed by EasyTier 2.6.4.
fn instance_config(id: Uuid) -> Option<TomlConfigLoader> {
    let service = CONTEXT.manager.get_instance_service(&id)?;
    CONTEXT.runtime.block_on(async {
        service
            .get_config_service()
            .get_config(Default::default(), Default::default())
            .await
            .ok()?
            .config?
            .gen_config()
            .ok()
    })
}

fn spawn_instance_event_forwarder(id: Uuid, notify_stop: bool) {
    let Some(mut events) = CONTEXT
        .manager
        .iter()
        .find(|instance| *instance.key() == id)
        .and_then(|instance| instance.subscribe_event())
    else {
        return;
    };
    CONTEXT.runtime.spawn(async move {
        loop {
            match events.recv().await {
                Ok(
                    GlobalCtxEvent::DhcpIpv4Changed(_, _)
                    | GlobalCtxEvent::ProxyCidrsUpdated(_, _)
                    | GlobalCtxEvent::ConfigPatched(_),
                ) => {
                    if let Ok(callback) = RUNNING_INFO_CALLBACK.lock() {
                        if let Some(callback) = *callback {
                            callback();
                        }
                    }
                }
                Ok(_) => {}
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    if notify_stop {
                        if let Ok(callback) = STOP_CALLBACK.lock() {
                            if let Some(callback) = *callback {
                                callback();
                            }
                        }
                    }
                    break;
                }
            }
        }
    });
}

#[no_mangle]
pub extern "C" fn init_logger(
    path: *const c_char,
    level: *const c_char,
    subsystem: *const c_char,
    err_msg: *mut *const c_char,
) -> c_int {
    let result = (|| -> Result<(), String> {
        if path.is_null() || level.is_null() || subsystem.is_null() {
            return Err("logger argument is null".to_string());
        }
        if LOGGER_FILE
            .lock()
            .map_err(|error| error.to_string())?
            .is_some()
        {
            return Ok(());
        }
        let path = unsafe { CStr::from_ptr(path) }.to_string_lossy();
        let level = unsafe { CStr::from_ptr(level) }.to_string_lossy();
        let subsystem = unsafe { CStr::from_ptr(subsystem) }.to_string_lossy();
        let file = Arc::new(Mutex::new(
            File::create(path.as_ref()).map_err(|error| error.to_string())?,
        ));
        let collector = tracing_subscriber::registry()
            .with(tracing_subscriber::EnvFilter::new(level.as_ref()))
            .with(
                tracing_subscriber::fmt::layer()
                    .with_writer(SharedLogWriter { file: file.clone() })
                    .with_ansi(false),
            )
            .with(OsLogger::new(subsystem.as_ref(), "rust"));
        tracing::subscriber::set_global_default(collector).map_err(|error| error.to_string())?;
        *LOGGER_FILE.lock().map_err(|error| error.to_string())? = Some(file);
        Ok(())
    })();
    ffi_result(result, err_msg)
}

#[no_mangle]
pub extern "C" fn clear_logger(err_msg: *mut *const c_char) -> c_int {
    ffi_result(
        (|| {
            let file = LOGGER_FILE
                .lock()
                .map_err(|error| error.to_string())?
                .clone()
                .ok_or_else(|| "logger is not initialized".to_string())?;
            let mut file = file.lock().map_err(|error| error.to_string())?;
            file.set_len(0).map_err(|error| error.to_string())?;
            file.seek(SeekFrom::Start(0))
                .map_err(|error| error.to_string())?;
            file.flush().map_err(|error| error.to_string())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn free_string(value: *const c_char) {
    if !value.is_null() {
        unsafe {
            drop(CString::from_raw(value as *mut c_char));
        }
    }
}

#[no_mangle]
pub extern "C" fn run_network_instance(
    cfg_str: *const c_char,
    err_msg: *mut *const c_char,
) -> c_int {
    ffi_result(
        (|| {
            if cfg_str.is_null() {
                return Err("cfg_str is null".to_string());
            }
            let config = unsafe { CStr::from_ptr(cfg_str) }.to_string_lossy();
            let config =
                TomlConfigLoader::new_from_str(&config).map_err(|error| error.to_string())?;
            let id = config.get_id();
            let mut mode = MODE.lock().map_err(|error| error.to_string())?;
            if !matches!(*mode, RunMode::Idle) {
                return Err("another EasyTier mode is already running".to_string());
            }
            CONTEXT
                .runtime
                .block_on(async {
                    CONTEXT.manager.run_network_instance(
                        config,
                        false,
                        ConfigFileControl::STATIC_CONFIG,
                    )
                })
                .map_err(|error| error.to_string())?;
            *mode = RunMode::Local(id);
            spawn_instance_event_forwarder(id, true);
            Ok(())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn start_config_server_client(
    url: *const c_char,
    hostname: *const c_char,
    machine_id: *const c_char,
    callback: ConfigServerCallback,
    err_msg: *mut *const c_char,
) -> c_int {
    ffi_result(
        (|| {
            if url.is_null() || machine_id.is_null() {
                return Err("config server URL and machine ID are required".to_string());
            }
            let url = unsafe { CStr::from_ptr(url) }
                .to_string_lossy()
                .trim()
                .to_string();
            let url = normalize_config_server_endpoint(&url)?;
            let machine_id = unsafe { CStr::from_ptr(machine_id) }
                .to_string_lossy()
                .trim()
                .to_string();
            let hostname = if hostname.is_null() {
                None
            } else {
                let value = unsafe { CStr::from_ptr(hostname) }
                    .to_string_lossy()
                    .trim()
                    .to_string();
                (!value.is_empty()).then_some(value)
            };
            if machine_id.is_empty() {
                return Err("machine ID is empty".to_string());
            }
            let mut mode = MODE.lock().map_err(|error| error.to_string())?;
            if !matches!(*mode, RunMode::Idle) {
                return Err("another EasyTier mode is already running".to_string());
            }
            let hooks = Arc::new(AppleWebHooks::new(CONTEXT.manager.clone(), callback));
            let client = CONTEXT
                .runtime
                .block_on(run_web_client(
                    &url,
                    MachineIdOptions {
                        explicit_machine_id: Some(machine_id),
                        state_dir: None,
                    },
                    hostname,
                    false,
                    CONTEXT.manager.clone(),
                    Some(hooks.clone()),
                ))
                .map_err(|error| error.to_string())?;
            *mode = RunMode::Web(ManagedWebClient { client, hooks });
            Ok(())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn is_config_server_client_connected() -> c_int {
    MODE.lock()
        .ok()
        .and_then(|mode| match &*mode {
            RunMode::Web(managed) => Some(managed.client.is_connected()),
            _ => None,
        })
        .map(i32::from)
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn complete_config_server_instance_setup(
    generation: u64,
    success: bool,
    error: *const c_char,
) -> c_int {
    let result = (|| {
        let message = if error.is_null() {
            "instance setup failed".to_string()
        } else {
            unsafe { CStr::from_ptr(error) }
                .to_string_lossy()
                .into_owned()
        };
        let mode = MODE.lock().map_err(|error| error.to_string())?;
        let RunMode::Web(managed) = &*mode else {
            return Err("config server client is not running".to_string());
        };
        managed
            .hooks
            .complete_setup(generation, if success { Ok(()) } else { Err(message) })
    })();
    if let Err(error) = result {
        tracing::warn!(%error, generation, "setup acknowledgement rejected");
        return -1;
    }
    0
}

#[derive(Serialize)]
struct TunnelOptions {
    ipv4: Option<String>,
    ipv6: Option<String>,
    mtu: Option<u16>,
    routes: Vec<String>,
    #[serde(rename = "magicDNS")]
    magic_dns: bool,
    dns: Vec<String>,
}

#[derive(Serialize)]
struct ConfigServerStatus {
    status: &'static str,
    #[serde(rename = "serverConnected")]
    server_connected: bool,
    #[serde(rename = "instanceID")]
    instance_id: Option<String>,
    #[serde(rename = "instanceName")]
    instance_name: Option<String>,
    #[serde(rename = "networkName")]
    network_name: Option<String>,
    generation: u64,
    error: Option<String>,
    options: Option<TunnelOptions>,
}

#[no_mangle]
pub extern "C" fn get_config_server_status(
    json: *mut *const c_char,
    err_msg: *mut *const c_char,
) -> c_int {
    ffi_result(
        (|| {
            if json.is_null() {
                return Err("json is null".to_string());
            }
            let mode = MODE.lock().map_err(|error| error.to_string())?;
            let RunMode::Web(managed) = &*mode else {
                return Err("config server client is not running".to_string());
            };
            let connected = managed.client.is_connected();
            let active = managed
                .hooks
                .active
                .lock()
                .map_err(|error| error.to_string())?
                .clone();
            let error = managed
                .hooks
                .last_error
                .lock()
                .map_err(|error| error.to_string())?
                .clone();
            let options = active
                .as_ref()
                .and_then(|metadata| instance_config(metadata.instance_id))
                .map(|config| {
                    let flags = config.get_flags();
                    TunnelOptions {
                        ipv4: config.get_ipv4().map(|value| value.to_string()),
                        ipv6: config.get_ipv6().map(|value| value.to_string()),
                        mtu: Some(flags.mtu as u16),
                        routes: config
                            .get_routes()
                            .unwrap_or_default()
                            .into_iter()
                            .map(|value| value.to_string())
                            .collect(),
                        magic_dns: flags.accept_dns,
                        dns: Vec::new(),
                    }
                });
            let status = ConfigServerStatus {
                status: if error.is_some() {
                    "error"
                } else if active.is_some() {
                    "running"
                } else if connected {
                    "waiting_config"
                } else {
                    "connecting_server"
                },
                server_connected: connected,
                instance_id: active.as_ref().map(|item| item.instance_id.to_string()),
                instance_name: active.as_ref().map(|item| item.instance_name.clone()),
                network_name: active.as_ref().map(|item| item.network_name.clone()),
                generation: active
                    .as_ref()
                    .map(|item| item.generation)
                    .unwrap_or_else(|| managed.hooks.generation.load(Ordering::Acquire)),
                error,
                options,
            };
            let value =
                CString::new(serde_json::to_string(&status).map_err(|error| error.to_string())?)
                    .map_err(|error| error.to_string())?;
            unsafe {
                *json = value.into_raw();
            }
            Ok(())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn set_tun_fd(fd: c_int, err_msg: *mut *const c_char) -> c_int {
    ffi_result(
        active_instance_id().and_then(|id| {
            CONTEXT
                .manager
                .set_tun_fd(&id, fd)
                .map_err(|error| error.to_string())
        }),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn stop_network_instance() -> c_int {
    let previous = match MODE.lock() {
        Ok(mut mode) => std::mem::replace(&mut *mode, RunMode::Idle),
        Err(_) => return -1,
    };
    let ids = match &previous {
        RunMode::Idle => return 0,
        RunMode::Local(id) => vec![*id],
        RunMode::Web(managed) => managed.hooks.stop(),
    };
    let result = CONTEXT.manager.delete_network_instance(ids);
    drop(previous);
    if result.is_ok() {
        0
    } else {
        -1
    }
}

#[no_mangle]
pub extern "C" fn register_stop_callback(
    callback: VoidCallback,
    err_msg: *mut *const c_char,
) -> c_int {
    ffi_result(
        (|| {
            let callback = callback.ok_or_else(|| "callback is null".to_string())?;
            *STOP_CALLBACK.lock().map_err(|error| error.to_string())? = Some(callback);
            Ok(())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn register_running_info_callback(
    callback: VoidCallback,
    err_msg: *mut *const c_char,
) -> c_int {
    ffi_result(
        (|| {
            let callback = callback.ok_or_else(|| "callback is null".to_string())?;
            *RUNNING_INFO_CALLBACK
                .lock()
                .map_err(|error| error.to_string())? = Some(callback);
            Ok(())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn get_running_info(json: *mut *const c_char, err_msg: *mut *const c_char) -> c_int {
    ffi_result(
        (|| {
            if json.is_null() {
                return Err("json is null".to_string());
            }
            let id = active_instance_id()?;
            let infos = CONTEXT
                .manager
                .collect_network_infos_sync()
                .map_err(|error| error.to_string())?;
            let info = infos
                .get(&id)
                .ok_or_else(|| "running info is unavailable".to_string())?;
            let value =
                CString::new(serde_json::to_string(info).map_err(|error| error.to_string())?)
                    .map_err(|error| error.to_string())?;
            unsafe {
                *json = value.into_raw();
            }
            Ok(())
        })(),
        err_msg,
    )
}

#[no_mangle]
pub extern "C" fn get_latest_error_msg(
    msg: *mut *const c_char,
    err_msg: *mut *const c_char,
) -> c_int {
    ffi_result(
        (|| {
            if msg.is_null() {
                return Err("msg is null".to_string());
            }
            let id = active_instance_id()?;
            let latest = CONTEXT
                .manager
                .iter()
                .find(|instance| *instance.key() == id)
                .and_then(|instance| instance.get_latest_error_msg());
            unsafe {
                *msg = match latest {
                    Some(value) => CString::new(value)
                        .map_err(|error| error.to_string())?
                        .into_raw(),
                    None => std::ptr::null(),
                };
            }
            Ok(())
        })(),
        err_msg,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_full_url_and_short_token() {
        assert_eq!(
            normalize_config_server_endpoint("udp://127.0.0.1:22020/token").unwrap(),
            "udp://127.0.0.1:22020/token"
        );
        assert_eq!(
            normalize_config_server_endpoint("token").unwrap(),
            "udp://config-server.easytier.cn:22020/token"
        );
        assert!(normalize_config_server_endpoint("").is_err());
        assert!(normalize_config_server_endpoint("bad/token").is_err());
    }

    #[test]
    fn rejects_unsupported_scheme_and_missing_token() {
        for endpoint in [
            "https://example.com/token",
            "udp://127.0.0.1:22020",
            "udp://127.0.0.1:22020/",
        ] {
            assert!(
                normalize_config_server_endpoint(endpoint).is_err(),
                "{endpoint}"
            );
        }
    }

    #[test]
    fn status_names_are_stable() {
        for status in ["connecting_server", "waiting_config", "running", "error"] {
            assert!(!status.is_empty());
        }
    }

    #[tokio::test]
    async fn web_hooks_allow_same_instance_and_reject_another() {
        let hooks = AppleWebHooks::new(CONTEXT.manager.clone(), None);
        let current_id = Uuid::new_v4();
        *hooks.active.lock().unwrap() = Some(InstanceMetadata {
            instance_id: current_id,
            instance_name: "current".to_string(),
            network_name: "test".to_string(),
            generation: 1,
        });
        let same = TomlConfigLoader::default();
        same.set_id(current_id);
        assert!(hooks.pre_run_network_instance(&same).await.is_ok());

        let another = TomlConfigLoader::default();
        another.set_id(Uuid::new_v4());
        assert!(hooks.pre_run_network_instance(&another).await.is_err());
    }

    #[tokio::test]
    async fn setup_acknowledgement_rejects_stale_generation() {
        let hooks = AppleWebHooks::new(CONTEXT.manager.clone(), None);
        let (sender, receiver) = oneshot::channel();
        *hooks.pending.lock().unwrap() = Some(PendingSetup {
            generation: 7,
            instance_id: Uuid::new_v4(),
            sender,
        });
        assert!(hooks.complete_setup(6, Ok(())).is_err());
        assert!(hooks.complete_setup(7, Ok(())).is_ok());
        assert_eq!(receiver.await.unwrap(), Ok(()));
    }

    #[tokio::test]
    async fn stop_cancels_pending_setup_and_drains_active_instance() {
        let hooks = AppleWebHooks::new(CONTEXT.manager.clone(), None);
        let instance_id = Uuid::new_v4();
        let (sender, receiver) = oneshot::channel();
        *hooks.pending.lock().unwrap() = Some(PendingSetup {
            generation: 1,
            instance_id,
            sender,
        });
        *hooks.active.lock().unwrap() = Some(InstanceMetadata {
            instance_id,
            instance_name: "current".to_string(),
            network_name: "test".to_string(),
            generation: 1,
        });
        assert_eq!(hooks.stop(), vec![instance_id]);
        assert!(receiver.await.unwrap().is_err());
        assert!(hooks.active.lock().unwrap().is_none());
    }

    #[test]
    fn status_serialization_uses_public_contract_keys() {
        let value = serde_json::to_value(ConfigServerStatus {
            status: "waiting_config",
            server_connected: true,
            instance_id: None,
            instance_name: None,
            network_name: None,
            generation: 3,
            error: None,
            options: None,
        })
        .unwrap();
        assert_eq!(value["status"], "waiting_config");
        assert_eq!(value["serverConnected"], true);
        assert_eq!(value["generation"], 3);
    }
}
