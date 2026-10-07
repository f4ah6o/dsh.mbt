///|
/// Thin native-only adapters for primitives missing from the portable async
/// filesystem. Paths passed to C are NUL-terminated UTF-8 byte strings.
#borrow(path)
extern "C" fn c_open_root(path : Bytes) -> Int = "dsh_fs_open_root"

///|
extern "C" fn c_close(fd : Int) -> Int = "dsh_fs_close"

///|
extern "C" fn c_set_root_mode(fd : Int, mode : Int) -> Int = "dsh_fs_set_root_mode"

///|
extern "C" fn c_pid() -> Int = "dsh_os_pid"

///|
extern "C" fn c_uid() -> Int = "dsh_os_uid"

///|
extern "C" fn c_flush_stdout() -> Int = "dsh_os_flush_stdout"

///|
fn native_flush_stdout() -> Unit {
  ignore(c_flush_stdout())
}

///|
#borrow(path)
extern "C" fn c_root_matches(root : Int, path : Bytes) -> Int = "dsh_fs_root_matches"

///|
#borrow(root_path, relative_path)
extern "C" fn c_mapping_matches(
  root : Int,
  root_path : Bytes,
  relative_path : Bytes,
  is_directory : Int,
) -> Int = "dsh_fs_mapping_matches"

///|
#borrow(buffer)
extern "C" fn c_hostname(buffer : FixedArray[Byte], capacity : Int) -> Int = "dsh_os_hostname"

///|
#borrow(buffer)
extern "C" fn c_timestamp(buffer : FixedArray[Byte], capacity : Int) -> Int = "dsh_os_timestamp"

///|
extern "C" fn c_process_alive(pid : Int) -> Int = "dsh_os_process_alive"

///|
extern "C" fn c_hard_worker_memory_supported() -> Int = "dsh_os_hard_worker_memory_supported"

///|
extern "C" fn c_kill_process_group(pid : Int, signal_number : Int) -> Int = "dsh_kill_process_group"

///|
extern "C" fn c_kill_process(pid : Int, signal_number : Int) -> Int = "dsh_kill_process"

///|
#borrow(payload)
extern "C" fn c_exec_worker(payload : Bytes, length : Int) -> Int = "dsh_exec_worker"

///|
#borrow(path)
extern "C" fn c_open_file(root : Int, path : Bytes) -> Int = "dsh_fs_open_file"

///|
#borrow(out)
extern "C" fn c_stat_fd(fd : Int, out : FixedArray[Int64]) -> Int = "dsh_fs_stat_fd"

///|
#borrow(out)
extern "C" fn c_stat_root(fd : Int, out : FixedArray[Int64]) -> Int = "dsh_fs_stat_root"

///|
#borrow(buffer)
extern "C" fn c_read_fd(
  fd : Int,
  buffer : FixedArray[Byte],
  capacity : Int,
) -> Int = "dsh_fs_read_fd"

///|
#borrow(root_path, path, data, expected)
extern "C" fn c_atomic_write(
  root : Int,
  root_path : Bytes,
  path : Bytes,
  data : Bytes,
  length : Int,
  mode : Int,
  create_parents : Int,
  has_expected : Int,
  force_mode : Int,
  expected : FixedArray[Int64],
) -> Int = "dsh_fs_atomic_write"

///|
#borrow(path, data)
extern "C" fn c_create_exclusive(
  root : Int,
  path : Bytes,
  data : Bytes,
  length : Int,
  mode : Int,
) -> Int = "dsh_fs_create_exclusive"

///|
#borrow(path)
extern "C" fn c_unlink(root : Int, path : Bytes) -> Int = "dsh_fs_unlink"

///|
#borrow(path, buffer)
extern "C" fn c_list_dir(
  root : Int,
  path : Bytes,
  buffer : FixedArray[Byte],
  capacity : Int,
) -> Int = "dsh_fs_list_dir"

///|
#borrow(data, output)
extern "C" fn c_sha256(
  data : Bytes,
  length : Int,
  output : FixedArray[Byte],
) -> Int = "dsh_crypto_sha256"

///|
#borrow(modulus, exponent, message, signature)
extern "C" fn c_verify_rs256(
  modulus : Bytes,
  modulus_len : Int,
  exponent : Bytes,
  exponent_len : Int,
  message : Bytes,
  message_len : Int,
  signature : Bytes,
  signature_len : Int,
) -> Int = "dsh_crypto_verify_rs256"

///|
#borrow(path)
fn c_path(path : String) -> Bytes {
  @utf8.encode(path) + b"\x00"
}

///|
fn bytes_from_fixedarray(buffer : FixedArray[Byte], length : Int) -> Bytes {
  let bytes : Array[Byte] = []
  for index = 0; index < length; index = index + 1 {
    bytes.push(buffer[index])
  }
  Bytes::from_array(bytes[:])
}

///|
pub struct FileVersion {
  priv fields : FixedArray[Int64]
}

///|
pub fn FileVersion::same(self : FileVersion, other : FileVersion) -> Bool {
  for index = 0; index < 10; index = index + 1 {
    if self.fields[index] != other.fields[index] {
      return false
    }
  }
  true
}

///|
pub fn FileVersion::size(self : FileVersion) -> Int64 {
  self.fields[2]
}

///|
pub fn FileVersion::device(self : FileVersion) -> Int64 {
  self.fields[0]
}

///|
pub fn FileVersion::inode(self : FileVersion) -> Int64 {
  self.fields[1]
}

///|
pub fn FileVersion::permission(self : FileVersion) -> Int {
  (self.fields[7] & 0o777).to_int()
}

///|
pub fn FileVersion::owner_uid(self : FileVersion) -> Int {
  self.fields[8].to_int()
}

///|
pub fn FileVersion::owner_gid(self : FileVersion) -> Int {
  self.fields[9].to_int()
}

///|
pub struct SafeRoot {
  priv fd : Int
  priv path : String
  priv mut closed : Bool
}

///|
pub fn SafeRoot::open(path : String) -> Result[SafeRoot, String] {
  if !path.has_prefix("/") {
    return Err("workspace root must be an absolute path")
  }
  let fd = c_open_root(c_path(path))
  if fd < 0 {
    Err(os_error("open workspace root", -fd))
  } else {
    Ok({ fd, path, closed: false, })
  }
}

///|
pub fn SafeRoot::path(self : SafeRoot) -> String {
  self.path
}

///|
pub fn SafeRoot::identity(self : SafeRoot) -> Result[(Int64, Int64), String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let fields : FixedArray[Int64] = FixedArray::make(10, 0)
  let status = c_stat_root(self.fd, fields)
  if status != 0 {
    Err(os_error("stat workspace root", status))
  } else {
    Ok((fields[0], fields[1]))
  }
}

///|
pub fn SafeRoot::close(self : SafeRoot) -> Unit {
  if !self.closed {
    self.closed = true
    ignore(c_close(self.fd))
  }
}

///|
pub fn SafeRoot::restrict_owner_only(self : SafeRoot) -> Result[Unit, String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let status = c_set_root_mode(self.fd, 0o700)
  if status == 0 {
    Ok(())
  } else {
    Err(os_error("protect data directory", status))
  }
}

///|
pub fn SafeRoot::create_exclusive(
  self : SafeRoot,
  relative_path : String,
  content : String,
  permission? : Int = 0o600,
) -> Result[Unit, String] {
  match self.create_exclusive_code(relative_path, content, permission~) {
    Ok(_) => Ok(())
    Err(code) => Err(os_error("exclusive file create", code))
  }
}

///|
pub fn SafeRoot::create_exclusive_code(
  self : SafeRoot,
  relative_path : String,
  content : String,
  permission? : Int = 0o600,
) -> Result[Unit, Int] {
  match self.ensure_open() {
    Err(_) => return Err(9)
    Ok(_) => ()
  }
  match self.verify_mapping(relative_path, false) {
    Err(_) => return Err(116)
    Ok(_) => ()
  }
  let data = @utf8.encode(content)
  let status = c_create_exclusive(
    self.fd,
    c_path(relative_path),
    data,
    data.length(),
    permission,
  )
  if status == 0 {
    match self.verify_mapping(relative_path, false) {
      Ok(_) => Ok(())
      Err(_) => Err(5)
    }
  } else {
    Err(status)
  }
}

///|
pub fn SafeRoot::unlink(
  self : SafeRoot,
  relative_path : String,
) -> Result[Unit, String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.verify_mapping(relative_path, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let status = c_unlink(self.fd, c_path(relative_path))
  if status == 0 {
    self.verify_mapping(relative_path, false)
  } else {
    Err(os_error("unlink", status))
  }
}

///|
pub fn SafeRoot::unlink_missing_ok(
  self : SafeRoot,
  relative_path : String,
) -> Result[Unit, String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.verify_mapping(relative_path, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let status = c_unlink(self.fd, c_path(relative_path))
  if status == 0 || status == 2 {
    self.verify_mapping(relative_path, false)
  } else {
    Err(os_error("unlink", status))
  }
}

///|
pub fn os_pid() -> Int {
  c_pid()
}

///|
pub fn os_uid() -> Int {
  c_uid()
}

///|
pub fn os_hostname() -> Result[String, String] {
  let buffer : FixedArray[Byte] = FixedArray::make(256, b'\x00')
  let count = c_hostname(buffer, buffer.length())
  if count < 0 {
    return Err(os_error("hostname lookup", -count))
  }
  let bytes = bytes_from_fixedarray(buffer, count)
  let value = @utf8.decode(bytes) catch {
    _ => return Err("hostname is not valid UTF-8")
  }
  Ok(value)
}

///|
pub fn os_process_alive(pid : Int) -> Bool {
  c_process_alive(pid) != 0
}

///|
pub fn os_hard_worker_memory_supported() -> Bool {
  c_hard_worker_memory_supported() == 1
}

///|
pub fn os_kill_process_group(pid : Int, signal_number : Int) -> Bool {
  c_kill_process_group(pid, signal_number) == 0
}

///|
pub fn os_kill_process(pid : Int, signal_number : Int) -> Bool {
  c_kill_process(pid, signal_number) == 0
}

///|
fn native_exec_worker(payload : Bytes) -> Int {
  c_exec_worker(payload, payload.length())
}

///|
pub fn os_timestamp() -> Result[String, String] {
  let buffer : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  let count = c_timestamp(buffer, buffer.length())
  if count < 0 {
    return Err(os_error("UTC clock", -count))
  }
  let bytes = bytes_from_fixedarray(buffer, count)
  let value = @utf8.decode(bytes) catch {
    _ => return Err("UTC timestamp is not valid UTF-8")
  }
  Ok(value)
}

///|
fn SafeRoot::ensure_open(self : SafeRoot) -> Result[Unit, String] {
  if self.closed {
    Err("workspace root is closed")
  } else {
    let status = c_root_matches(self.fd, c_path(self.path))
    if status == 1 {
      Ok(())
    } else if status == 0 {
      Err("workspace directory changed during execution")
    } else {
      Err(os_error("verify workspace directory", -status))
    }
  }
}

///|
/// Confirm that a path's current directory chain still names the same inode
/// as the anchored dirfd walk. The check is repeated after IO by callers to
/// detect a nested directory moved during the operation.
fn SafeRoot::verify_mapping(
  self : SafeRoot,
  relative_path : String,
  is_directory : Bool,
) -> Result[Unit, String] {
  let status = c_mapping_matches(
    self.fd,
    c_path(self.path),
    c_path(relative_path),
    if is_directory {
      1
    } else {
      0
    },
  )
  if status == 1 {
    Ok(())
  } else if status == 0 {
    Err("workspace directory mapping changed during execution")
  } else {
    Err(os_error("verify workspace directory mapping", -status))
  }
}

///|
fn os_error(operation : String, code : Int) -> String {
  operation + " failed (OS error " + code.to_string() + ")"
}

///|
fn SafeRoot::open_regular(
  self : SafeRoot,
  relative_path : String,
) -> Result[Int, String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let fd = c_open_file(self.fd, c_path(relative_path))
  if fd < 0 {
    Err(os_error("open workspace file", -fd))
  } else {
    match self.verify_mapping(relative_path, false) {
      Ok(_) => Ok(fd)
      Err(error) => {
        ignore(c_close(fd))
        Err(error)
      }
    }
  }
}

///|
fn SafeRoot::stat(_self : SafeRoot, fd : Int) -> Result[FileVersion, String] {
  let fields : FixedArray[Int64] = FixedArray::make(10, 0)
  let status = c_stat_fd(fd, fields)
  if status != 0 {
    Err(os_error("stat workspace file", status))
  } else {
    Ok({ fields, })
  }
}

///|
pub fn SafeRoot::read_text(
  self : SafeRoot,
  relative_path : String,
  max_bytes? : Int = 1048576,
) -> Result[(String, FileVersion), String] {
  if max_bytes < 0 || max_bytes > 33554432 {
    return Err("invalid workspace read limit")
  }
  let fd = match self.open_regular(relative_path) {
    Ok(fd) => fd
    Err(error) => return Err(error)
  }
  defer ignore(c_close(fd))
  let before = match self.stat(fd) {
    Ok(version) => version
    Err(error) => return Err(error)
  }
  if before.size() > max_bytes.to_int64() {
    return Err("workspace file exceeds the read limit")
  }
  let capacity = before.size().to_int() + 1
  let buffer : FixedArray[Byte] = FixedArray::make(capacity, b'\x00')
  let count = c_read_fd(fd, buffer, capacity)
  if count < 0 {
    return Err(os_error("read workspace file", -count))
  }
  if count > max_bytes {
    return Err("workspace file exceeds the read limit")
  }
  let after = match self.stat(fd) {
    Ok(version) => version
    Err(error) => return Err(error)
  }
  if !before.same(after) || count.to_int64() != before.size() {
    return Err("workspace file changed while being read")
  }
  match self.verify_mapping(relative_path, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for index = 0; index < count; index = index + 1 {
    if buffer[index] == b'\x00' {
      return Err("binary files are not supported by the text tool")
    }
  }
  let bytes = bytes_from_fixedarray(buffer, count)
  let text = @utf8.decode(bytes) catch {
    _ => return Err("workspace file is not valid UTF-8")
  }
  Ok((text, before))
}

///|
pub fn SafeRoot::read_text_optional(
  self : SafeRoot,
  relative_path : String,
  max_bytes? : Int = 1048576,
) -> Result[(String, FileVersion)?, String] {
  if max_bytes < 0 || max_bytes > 33554432 {
    return Err("invalid workspace read limit")
  }
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.verify_mapping(relative_path, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let fd = c_open_file(self.fd, c_path(relative_path))
  if fd == -2 {
    return Ok(None)
  }
  if fd < 0 {
    return Err(os_error("open workspace file", -fd))
  }
  defer ignore(c_close(fd))
  let before = match self.stat(fd) {
    Ok(version) => version
    Err(error) => return Err(error)
  }
  if before.size() > max_bytes.to_int64() {
    return Err("workspace file exceeds the read limit")
  }
  let capacity = before.size().to_int() + 1
  let buffer : FixedArray[Byte] = FixedArray::make(capacity, b'\x00')
  let count = c_read_fd(fd, buffer, capacity)
  if count < 0 {
    return Err(os_error("read workspace file", -count))
  }
  let after = match self.stat(fd) {
    Ok(version) => version
    Err(error) => return Err(error)
  }
  if !before.same(after) || count.to_int64() != before.size() {
    return Err("workspace file changed while being read")
  }
  match self.verify_mapping(relative_path, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  for index = 0; index < count; index = index + 1 {
    if buffer[index] == b'\x00' {
      return Err("binary files are not supported by the text tool")
    }
  }
  let bytes = bytes_from_fixedarray(buffer, count)
  let text = @utf8.decode(bytes) catch {
    _ => return Err("workspace file is not valid UTF-8")
  }
  Ok(Some((text, before)))
}

///|
/// Read an existing protected file only when it is a regular, non-symlink
/// file owned by this user with no group or world permissions.
pub fn SafeRoot::read_protected_text(
  self : SafeRoot,
  relative_path : String,
  max_bytes? : Int = 1048576,
) -> Result[String?, String] {
  match self.read_text_optional(relative_path, max_bytes~) {
    Err(error) => Err(error)
    Ok(None) => Ok(None)
    Ok(Some((text, version))) =>
      if version.owner_uid() != os_uid() {
        Err("protected file is not owned by the current user")
      } else if version.permission() != 0o600 {
        Err("protected file must have mode 0600")
      } else {
        Ok(Some(text))
      }
  }
}

///|
pub fn SafeRoot::list_directory(
  self : SafeRoot,
  relative_path : String,
) -> Result[Array[(String, String)], String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.verify_mapping(relative_path, true) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let buffer : FixedArray[Byte] = FixedArray::make(1048576, b'\x00')
  let count = c_list_dir(
    self.fd,
    c_path(relative_path),
    buffer,
    buffer.length(),
  )
  if count < 0 {
    return Err(os_error("list workspace directory", -count))
  }
  match self.verify_mapping(relative_path, true) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let entries : Array[(String, String)] = []
  let mut offset = 0
  while offset < count {
    let start = offset
    while offset < count && buffer[offset] != b'\x00' {
      offset += 1
    }
    if offset >= count || offset + 1 >= count {
      return Err("native directory listing returned a malformed entry")
    }
    let length = offset - start
    let kind_byte = buffer[offset + 1]
    let name_array : FixedArray[Byte] = FixedArray::makei(length, index => {
      buffer[start + index]
    })
    let name_bytes = bytes_from_fixedarray(name_array, name_array.length())
    let name = @utf8.decode(name_bytes) catch {
      _ => return Err("workspace contains a non-UTF-8 filename")
    }
    let kind = if kind_byte == b'D' { "directory" } else { "file" }
    entries.push((name, kind))
    offset += 2
  }
  Ok(entries)
}

///|
pub fn SafeRoot::write_atomic(
  self : SafeRoot,
  relative_path : String,
  content : String,
  expected? : FileVersion,
  create_parents? : Bool = false,
  permission? : Int = 0o644,
) -> Result[Unit, String] {
  match expected {
    Some(version) =>
      self.write_atomic_bounded(
        relative_path,
        content,
        1048576,
        expected=version,
        create_parents~,
        permission~,
      )
    None =>
      self.write_atomic_bounded(
        relative_path,
        content,
        1048576,
        create_parents~,
        permission~,
      )
  }
}

///|
/// Atomically write host-managed data with an explicit bounded size. Workspace
/// tools use `write_atomic` and retain their 1 MiB per-file limit; the durable
/// host envelope uses this method for its separate 32 MiB snapshot budget.
pub fn SafeRoot::write_atomic_bounded(
  self : SafeRoot,
  relative_path : String,
  content : String,
  max_bytes : Int,
  expected? : FileVersion,
  create_parents? : Bool = false,
  permission? : Int = 0o644,
) -> Result[Unit, String] {
  if max_bytes < 0 || max_bytes > 33554432 {
    return Err("invalid atomic write limit")
  }
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let data = @utf8.encode(content)
  if data.length() > max_bytes {
    return Err("atomic write exceeds the configured byte limit")
  }
  if !create_parents {
    match self.verify_mapping(relative_path, false) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  let version : FixedArray[Int64] = match expected {
    Some(value) => value.fields
    None => FixedArray::make(10, 0)
  }
  let status = c_atomic_write(
    self.fd,
    c_path(self.path),
    c_path(relative_path),
    data,
    data.length(),
    permission,
    if create_parents {
      1
    } else {
      0
    },
    if expected is Some(_) {
      1
    } else {
      0
    },
    0,
    version,
  )
  if status == 0 {
    Ok(())
  } else {
    Err(os_error("atomic workspace write", status))
  }
}

///|
pub fn SafeRoot::write_atomic_protected(
  self : SafeRoot,
  relative_path : String,
  content : String,
) -> Result[Unit, String] {
  match self.ensure_open() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let data = @utf8.encode(content)
  if data.length() > 1048576 {
    return Err("protected credential file exceeds the size limit")
  }
  match self.verify_mapping(relative_path, false) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let version : FixedArray[Int64] = FixedArray::make(10, 0)
  let status = c_atomic_write(
    self.fd,
    c_path(self.path),
    c_path(relative_path),
    data,
    data.length(),
    0o600,
    0,
    0,
    1,
    version,
  )
  if status == 0 {
    Ok(())
  } else {
    Err(os_error("protected credential write", status))
  }
}

///|
pub fn SafeRoot::sha256(data : Bytes) -> Result[Bytes, String] {
  let output : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  if c_sha256(data, data.length(), output) == 0 {
    Err("system SHA-256 provider is unavailable")
  } else {
    Ok(bytes_from_fixedarray(output, output.length()))
  }
}

///|
pub fn SafeRoot::verify_rs256(
  modulus : Bytes,
  exponent : Bytes,
  message : Bytes,
  signature : Bytes,
) -> Bool {
  c_verify_rs256(
    modulus,
    modulus.length(),
    exponent,
    exponent.length(),
    message,
    message.length(),
    signature,
    signature.length(),
  ) ==
  1
}
