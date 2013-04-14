
-- Linux syscall ABI ffi interface

local S = {} -- exported functions

local ffi = require "ffi"
local bit = require "bit"

local C = require "syscall.c"
S.C = C

local c = require "syscall.constants"
S.c = c

local types = require "syscall.types"
S.t, S.pt, S.s, S.ctypes = types.t, types.pt, types.s, types.ctypes -- types, pointer types and sizes tables and ctypes map
local t, pt, s = S.t, S.pt, S.s

local h = require "syscall.helpers"
local split = h.split

-- makes code tidier TODO could return constructed type if not that type to simplify usage.
local function istype(tp, x)
  if ffi.istype(tp, x) then return x end
  return false
end

local function getfd(fd)
  if type(fd) == "number" or ffi.istype(t.int, fd) then return fd end
  return fd:getfd()
end

-- typed values for pointer comparison
local zeropointer = pt.void(0)
local errpointer = pt.void(-1)

-- return helpers.

-- straight passthrough, only needed for real 64 bit quantities. Used eg for seek (file might have giant holes!)
local function ret64(ret)
  if ret == t.uint64(-1) then return nil, t.error() end
  return ret
end

local function retnum(ret) -- return Lua number where double precision ok, eg file ops etc
  ret = tonumber(ret)
  if ret == -1 then return nil, t.error() end
  return ret
end

local function retfd(ret)
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

-- used for no return value, return true for use of assert
local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

-- used for pointer returns, -1 is failure
local function retptr(ret)
  if ret == errpointer then return nil, t.error() end
  return ret
end

-- main definitions start here
if ffi.abi("32bit") then
  function S.open(pathname, flags, mode)
    flags = bit.bor(c.O[flags], c.O.LARGEFILE)
    return retfd(C.open(pathname, flags, c.MODE[mode]))
  end
  function S.openat(dirfd, pathname, flags, mode)
    flags = bit.bor(c.O[flags], c.O.LARGEFILE)
    return retfd(C.openat(c.AT_FDCWD[dirfd], pathname, flags, c.MODE[mode]))
  end
  function S.creat(pathname, mode)
    return retfd(C.open(pathname, c.O["CREAT,WRONLY,TRUNC,LARGEFILE"], c.MODE[mode]))
  end
else -- no largefile issues
  function S.open(pathname, flags, mode)
    return retfd(C.open(pathname, c.O[flags], c.MODE[mode]))
  end
  function S.openat(dirfd, pathname, flags, mode)
    return retfd(C.openat(c.AT_FDCWD[dirfd], pathname, c.O[flags], c.MODE[mode]))
  end
  function S.creat(pathname, mode) return retfd(C.creat(pathname, c.MODE[mode])) end
end

-- TODO dup3 can have a race condition (see man page) although Musl fixes, appears eglibc does not
function S.dup(oldfd, newfd, flags)
  if not newfd then return retfd(C.dup(getfd(oldfd))) end
  return retfd(C.dup3(getfd(oldfd), getfd(newfd), flags or 0))
end

function S.pipe(flags)
  local fd2 = t.int2()
  local ret = C.pipe2(fd2, c.OPIPE[flags])
  if ret == -1 then return nil, t.error() end
  return t.pipe(fd2)
end

function S.close(fd) return retbool(C.close(getfd(fd))) end

function S.unlink(pathname) return retbool(C.unlink(pathname)) end
function S.unlinkat(dirfd, path, flags)
  return retbool(C.unlinkat(c.AT_FDCWD[dirfd], path, c.AT_REMOVEDIR[flags]))
end
function S.rename(oldpath, newpath) return retbool(C.rename(oldpath, newpath)) end
function S.renameat(olddirfd, oldpath, newdirfd, newpath)
  return retbool(C.renameat(c.AT_FDCWD[olddirfd], oldpath, c.AT_FDCWD[newdirfd], newpath))
end
function S.chdir(path) return retbool(C.chdir(path)) end
function S.mkdir(path, mode) return retbool(C.mkdir(path, c.MODE[mode])) end
function S.mkdirat(fd, path, mode) return retbool(C.mkdirat(c.AT_FDCWD[fd], path, c.MODE[mode])) end
function S.rmdir(path) return retbool(C.rmdir(path)) end
function S.acct(filename) return retbool(C.acct(filename)) end
function S.chmod(path, mode) return retbool(C.chmod(path, c.MODE[mode])) end
function S.link(oldpath, newpath) return retbool(C.link(oldpath, newpath)) end
function S.linkat(olddirfd, oldpath, newdirfd, newpath, flags)
  return retbool(C.linkat(c.AT_FDCWD[olddirfd], oldpath, c.AT_FDCWD[newdirfd], newpath, c.AT_SYMLINK_FOLLOW[flags]))
end
function S.symlink(oldpath, newpath) return retbool(C.symlink(oldpath, newpath)) end
function S.symlinkat(oldpath, newdirfd, newpath) return retbool(C.symlinkat(oldpath, c.AT_FDCWD[newdirfd], newpath)) end
function S.pause() return retbool(C.pause()) end

function S.chown(path, owner, group) return retbool(C.chown(path, owner or -1, group or -1)) end
function S.fchown(fd, owner, group) return retbool(C.fchown(getfd(fd), owner or -1, group or -1)) end
function S.lchown(path, owner, group) return retbool(C.lchown(path, owner or -1, group or -1)) end
function S.fchownat(dirfd, path, owner, group, flags)
  return retbool(C.fchownat(c.AT_FDCWD[dirfd], path, owner or -1, group or -1, c.AT_SYMLINK_NOFOLLOW[flags]))
end

function S.truncate(path, length) return retbool(C.truncate(path, length)) end
function S.ftruncate(fd, length) return retbool(C.ftruncate(getfd(fd), length)) end

function S.access(pathname, mode) return retbool(C.access(pathname, c.OK[mode])) end
function S.faccessat(dirfd, pathname, mode, flags)
  return retbool(C.faccessat(c.AT_FDCWD[dirfd], pathname, c.OK[mode], c.AT_ACCESSAT[flags]))
end

function S.readlink(path, buffer, size)
  size = size or c.PATH_MAX
  buffer = buffer or t.buffer(size)
  local ret = tonumber(C.readlink(path, buffer, size))
  if ret == -1 then return nil, t.error() end
  return ffi.string(buffer, ret)
end

function S.readlinkat(dirfd, path, buffer, size)
  size = size or c.PATH_MAX
  buffer = buffer or t.buffer(size)
  local ret = tonumber(C.readlinkat(c.AT_FDCWD[dirfd], path, buffer, size))
  if ret == -1 then return nil, t.error() end
  return ffi.string(buffer, ret)
end

function S.mknod(pathname, mode, dev)
  if type(dev) == "table" then dev = dev.dev end
  return retbool(C.mknod(pathname, c.S_I[mode], dev or 0))
end
function S.mknodat(fd, pathname, mode, dev)
  if type(dev) == "table" then dev = dev.dev end
  return retbool(C.mknodat(c.AT_FDCWD[fd], pathname, c.S_I[mode], dev or 0))
end

if C.nice then
  function S.nice(inc) return retbool(C.nice(inc)) end
else
  function S.nice(inc)
    local prio = S.getpriority(c.PRIO.PROCESS, 0) -- this cannot fail with these args. Call S. not C. as adjusted values
    return S.setpriority(c.PRIO.PROCESS, 0, prio + inc)
  end
end

function S.getpriority(which, who)
  local ret = C.getpriority(c.PRIO[which], who or 0)
  if ret == -1 then return nil, t.error() end
  return 20 - ret -- adjust for kernel returned values as this is syscall not libc
end
function S.setpriority(which, who, prio) return retbool(C.setpriority(c.PRIO[which], who or 0, prio)) end

 -- we could allocate ptid, ctid, tls if required in flags instead. TODO add signal into flag parsing directly?
function S.clone(flags, signal, stack, ptid, tls, ctid)
  flags = c.CLONE[flags] + c.SIG[signal]
  return retnum(C.clone(flags, stack, ptid, tls, ctid))
end

function S.unshare(flags) return retbool(C.unshare(c.CLONE[flags])) end
function S.setns(fd, nstype) return retbool(C.setns(getfd(fd), c.CLONE[nstype])) end

function S.fork() return retnum(C.fork()) end
function S.execve(filename, argv, envp)
  local cargv = t.string_array(#argv + 1, argv or {})
  cargv[#argv] = nil -- LuaJIT does not zero rest of a VLA
  local cenvp = t.string_array(#envp + 1, envp or {})
  cenvp[#envp] = nil
  return retbool(C.execve(filename, cargv, cenvp))
end

function S.ioctl(d, request, argp)
  if type(argp) == "string" then argp = pt.char(argp) end
  local ret = C.ioctl(getfd(d), c.IOCTL[request], argp)
  if ret == -1 then return nil, t.error() end
  return ret -- usually zero
end

-- note that this is not strictly the syscall that has some other arguments, but has same functionality
function S.reboot(cmd) return retbool(C.reboot(c.LINUX_REBOOT_CMD[cmd])) end

-- default behaviour is to iterate over whole directory, use noiter if you have very large directories
-- TODO maybe remove this from here, move to util instead
function S.getdents(fd, buf, size, noiter)
  size = size or 4096
  buf = buf or t.buffer(size)
  local d = {}
  local ret
  repeat
    ret = C.getdents(getfd(fd), buf, size)
    if ret == -1 then return nil, t.error() end
    local i = 0
    while i < ret do
      local dp = pt.dirent(buf + i)
      local dd = t.dent(dp)
      d[dd.name] = dd
      i = i + dp.d_reclen
    end
  until noiter or ret == 0
  return d
end

function S.wait()
  local status = t.int1()
  local ret = C.wait(status)
  if ret == -1 then return nil, t.error() end
  return t.wait(ret, status[0])
end
function S.waitpid(pid, options)
  local status = t.int1()
  local ret = C.waitpid(pid, status, c.W[options])
  if ret == -1 then return nil, t.error() end
  return t.wait(ret, status[0])
end
function S.waitid(idtype, id, options, infop) -- note order of args, as usually dont supply infop
  if not infop then infop = t.siginfo() end
  infop.si_pid = 0 -- see notes on man page
  local ret = C.waitid(c.P[idtype], id or 0, infop, c.W[options])
  if ret == -1 then return nil, t.error() end
  return infop -- return table here?
end

function S._exit(status) C._exit(c.EXIT[status]) end
function S.exit(status) C.exit_group(c.EXIT[status]) end

function S.read(fd, buf, count)
  if buf then return retnum(C.read(getfd(fd), buf, count)) end -- user supplied a buffer, standard usage
  if not count then count = 4096 end
  buf = t.buffer(count)
  local ret = C.read(getfd(fd), buf, count)
  if ret == -1 then return nil, t.error() end
  return ffi.string(buf, ret) -- user gets a string back, can get length from #string
end

function S.write(fd, buf, count) return retnum(C.write(getfd(fd), buf, count or #buf)) end
function S.pread(fd, buf, count, offset) return retnum(C.pread64(getfd(fd), buf, count, offset)) end
function S.pwrite(fd, buf, count, offset) return retnum(C.pwrite64(getfd(fd), buf, count or #buf, offset)) end

function S.lseek(fd, offset, whence)
  return ret64(C.lseek(getfd(fd), offset or 0, c.SEEK[whence]))
end

function S.send(fd, buf, count, flags) return retnum(C.send(getfd(fd), buf, count or #buf, c.MSG[flags])) end
function S.sendto(fd, buf, count, flags, addr, addrlen)
  return retnum(C.sendto(getfd(fd), buf, count or #buf, c.MSG[flags], addr, addrlen or ffi.sizeof(addr)))
end

function S.sendmsg(fd, msg, flags)
  if not msg then -- send a single byte message, eg enough to send credentials
    local buf1 = t.buffer(1)
    local io = t.iovecs{{buf1, 1}}
    msg = t.msghdr{msg_iov = io.iov, msg_iovlen = #io}
  end
  return retbool(C.sendmsg(getfd(fd), msg, c.MSG[flags]))
end

function S.recvmsg(fd, msg, flags) return retnum(C.recvmsg(getfd(fd), msg, c.MSG[flags])) end

function S.readv(fd, iov)
  iov = istype(t.iovecs, iov) or t.iovecs(iov)
  return retnum(C.readv(getfd(fd), iov.iov, #iov))
end

function S.writev(fd, iov)
  iov = istype(t.iovecs, iov) or t.iovecs(iov)
  return retnum(C.writev(getfd(fd), iov.iov, #iov))
end

function S.preadv(fd, iov, offset)
  iov = istype(t.iovecs, iov) or t.iovecs(iov)
  return retnum(C.preadv64(getfd(fd), iov.iov, #iov, offset))
end

function S.pwritev(fd, iov, offset)
  iov = istype(t.iovecs, iov) or t.iovecs(iov)
  return retnum(C.pwritev64(getfd(fd), iov.iov, #iov, offset))
end

function S.recv(fd, buf, count, flags) return retnum(C.recv(getfd(fd), buf, count or #buf, c.MSG[flags])) end
function S.recvfrom(fd, buf, count, flags, ss, addrlen)
  ss = ss or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#ss)
  local ret = C.recvfrom(getfd(fd), buf, count, c.MSG[flags], ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return {count = tonumber(ret), addr = t.sa(ss, addrlen[0])}
end

-- TODO {get,set}sockopt may need better type handling
function S.setsockopt(fd, level, optname, optval, optlen)
   -- allocate buffer for user, from Lua type if know how, int and bool so far
  if not optlen and type(optval) == 'boolean' then if optval then optval = 1 else optval = 0 end end
  if not optlen and type(optval) == 'number' then
    optval = t.int1(optval)
    optlen = s.int
  end
  return retbool(C.setsockopt(getfd(fd), c.SOL[level], c.SO[optname], optval, optlen))
end

function S.getsockopt(fd, level, optname, optval, optlen)
  if not optval then optval, optlen = t.int1(), s.int end
  optlen = optlen or #optval
  local len = t.socklen1(optlen)
  local ret = C.getsockopt(getfd(fd), level, optname, optval, len)
  if ret == -1 then return nil, t.error() end
  return optval[0]
end

function S.fchdir(fd) return retbool(C.fchdir(getfd(fd))) end
function S.fsync(fd) return retbool(C.fsync(getfd(fd))) end
function S.fdatasync(fd) return retbool(C.fdatasync(getfd(fd))) end
function S.fchmod(fd, mode) return retbool(C.fchmod(getfd(fd), c.MODE[mode])) end
function S.fchmodat(dirfd, pathname, mode)
  return retbool(C.fchmodat(c.AT_FDCWD[dirfd], pathname, c.MODE[mode], 0)) -- no flags actually supported
end
function S.sync_file_range(fd, offset, count, flags)
  return retbool(C.sync_file_range(getfd(fd), offset, count, c.SYNC_FILE_RANGE[flags]))
end

function S.stat(path, buf)
  if not buf then buf = t.stat() end
  local ret = C.stat(path, buf)
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.lstat(path, buf)
  if not buf then buf = t.stat() end
  local ret = C.lstat(path, buf)
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.fstat(fd, buf)
  if not buf then buf = t.stat() end
  local ret = C.fstat(getfd(fd), buf)
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.fstatat(fd, path, buf, flags)
  if not buf then buf = t.stat() end
  local ret = C.fstatat(c.AT_FDCWD[fd], path, buf, c.AT_FSTATAT[flags])
  if ret == -1 then return nil, t.error() end
  return buf
end

function S.futimens(fd, ts)
  if ts then ts = t.timespec2(ts) end
  return retbool(C.futimens(getfd(fd), ts))
end

function S.utimensat(dirfd, path, ts, flags)
  if ts then ts = t.timespec2(ts) end
  return retbool(C.utimensat(c.AT_FDCWD[dirfd], path, ts, c.AT_SYMLINK_NOFOLLOW[flags]))
end

-- because you can just pass floats to all the time functions, just use the same one, but provide different templates
function S.utime(path, actime, modtime)
  local ts
  if not modtime then modtime = actime end
  if actime and modtime then ts = {actime, modtime} end
  return S.utimensat(nil, path, ts)
end

S.utimes = S.utime

function S.chroot(path) return retbool(C.chroot(path)) end

function S.getcwd(buf, size)
  size = size or c.PATH_MAX
  buf = buf or t.buffer(size)
  local ret = C.getcwd(buf, size)
  if ret == -1 then return nil, t.error() end
  return ffi.string(buf)
end

function S.statfs(path)
  local st = t.statfs()
  local ret = C.statfs(path, st)
  if ret == -1 then return nil, t.error() end
  return st
end

function S.fstatfs(fd)
  local st = t.statfs()
  local ret = C.fstatfs(getfd(fd), st)
  if ret == -1 then return nil, t.error() end
  return st
end

function S.nanosleep(req, rem)
  req = istype(t.timespec, req) or t.timespec(req)
  rem = rem or t.timespec()
  local ret = C.nanosleep(req, rem)
  if ret == -1 then
    if ffi.errno() == c.E.INTR then return rem else return nil, t.error() end
  end
  return true
end

function S.sleep(sec) -- standard libc function
  local rem, err = S.nanosleep(sec)
  if not rem then return nil, err end
  if rem == true then return 0 end
  return tonumber(rem.tv_sec)
end

-- TODO return metatype that has length and can gc?
function S.mmap(addr, length, prot, flags, fd, offset)
  return retptr(C.mmap(addr, length, c.PROT[prot], c.MAP[flags], getfd(fd), offset))
end
function S.munmap(addr, length)
  return retbool(C.munmap(addr, length))
end
function S.msync(addr, length, flags) return retbool(C.msync(addr, length, c.MSYNC[flags])) end
function S.mlock(addr, len) return retbool(C.mlock(addr, len)) end
function S.munlock(addr, len) return retbool(C.munlock(addr, len)) end
function S.mlockall(flags) return retbool(C.mlockall(c.MCL[flags])) end
function S.munlockall() return retbool(C.munlockall()) end
function S.mremap(old_address, old_size, new_size, flags, new_address)
  return retptr(C.mremap(old_address, old_size, new_size, c.MREMAP[flags], new_address))
end
function S.madvise(addr, length, advice) return retbool(C.madvise(addr, length, c.MADV[advice])) end
function S.fadvise(fd, advice, offset, len) -- note argument order TODO change back?
  return retbool(C.fadvise64(getfd(fd), offset or 0, len or 0, c.POSIX_FADV[advice]))
end
function S.fallocate(fd, mode, offset, len)
  return retbool(C.fallocate(getfd(fd), c.FALLOC_FL[mode], offset or 0, len))
end
function S.posix_fallocate(fd, offset, len) return S.fallocate(fd, 0, offset, len) end
function S.readahead(fd, offset, count) return retbool(C.readahead(getfd(fd), offset, count)) end

local function sproto(domain, protocol) -- helper function to lookup protocol type depending on domain TODO table?
  protocol = protocol or 0
  if domain == c.AF.NETLINK then return c.NETLINK[protocol] end
  return c.IPPROTO[protocol]
end

function S.socket(domain, stype, protocol)
  domain = c.AF[domain]
  local ret = C.socket(domain, c.SOCK[stype], sproto(domain, protocol))
  if ret == -1 then return nil, t.error() end
  return t.fd(ret)
end

function S.socketpair(domain, stype, protocol)
  domain = c.AF[domain]
  local sv2 = t.int2()
  local ret = C.socketpair(domain, c.SOCK[stype], sproto(domain, protocol), sv2)
  if ret == -1 then return nil, t.error() end
  return t.socketpair(sv2)
end

function S.bind(sockfd, addr, addrlen)
  return retbool(C.bind(getfd(sockfd), addr, addrlen or ffi.sizeof(addr)))
end

function S.listen(sockfd, backlog) return retbool(C.listen(getfd(sockfd), backlog or c.SOMAXCONN)) end
function S.connect(sockfd, addr, addrlen)
  return retbool(C.connect(getfd(sockfd), addr, addrlen or ffi.sizeof(addr)))
end

function S.shutdown(sockfd, how) return retbool(C.shutdown(getfd(sockfd), c.SHUT[how])) end

function S.accept(sockfd, flags, addr, addrlen)
  if not addr then addr = t.sockaddr_storage() end
  if not addrlen then addrlen = t.socklen1(addrlen or ffi.sizeof(addr)) end
  local ret
  if not flags
    then ret = C.accept(getfd(sockfd), addr, addrlen)
    else ret = C.accept4(getfd(sockfd), addr, addrlen, c.SOCK[flags])
  end
  if ret == -1 then return nil, t.error() end
  return {fd = t.fd(ret), addr = t.sa(addr, addrlen[0])}
end

function S.getsockname(sockfd, ss, addrlen)
  ss = ss or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#ss)
  local ret = C.getsockname(getfd(sockfd), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return t.sa(ss, addrlen[0])
end

function S.getpeername(sockfd, ss, addrlen)
  ss = ss or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(#ss)
  local ret = C.getpeername(getfd(sockfd), ss, addrlen)
  if ret == -1 then return nil, t.error() end
  return t.sa(ss, addrlen[0])
end

-- TODO change to type
local function getflock(arg)
  if not arg then arg = t.flock() end
  if not ffi.istype(t.flock, arg) then
    for _, v in pairs {"type", "whence", "start", "len", "pid"} do -- allow use of short names
      if arg[v] then
        arg["l_" .. v] = arg[v] -- TODO cleanup this to use table?
        arg[v] = nil
      end
    end
    arg.l_type = c.FCNTL_LOCK[arg.l_type]
    arg.l_whence = c.SEEK[arg.l_whence]
    arg = t.flock(arg)
  end
  return arg
end

local fcntl_commands = {
  [c.F.SETFL] = function(arg) return c.O[arg] end,
  [c.F.SETFD] = function(arg) return c.FD[arg] end,
  [c.F.GETLK] = getflock,
  [c.F.SETLK] = getflock,
  [c.F.SETLKW] = getflock,
}

local fcntl_ret = {
  [c.F.DUPFD] = function(ret) return t.fd(ret) end,
  [c.F.DUPFD_CLOEXEC] = function(ret) return t.fd(ret) end,
  [c.F.GETFD] = function(ret) return tonumber(ret) end,
  [c.F.GETFL] = function(ret) return tonumber(ret) end,
  [c.F.GETLEASE] = function(ret) return tonumber(ret) end,
  [c.F.GETOWN] = function(ret) return tonumber(ret) end,
  [c.F.GETSIG] = function(ret) return tonumber(ret) end,
  [c.F.GETPIPE_SZ] = function(ret) return tonumber(ret) end,
  [c.F.GETLK] = function(ret, arg) return arg end,
}

function S.fcntl(fd, cmd, arg)
  cmd = c.F[cmd]

  if fcntl_commands[cmd] then arg = fcntl_commands[cmd](arg) end

  local ret = C.fcntl(getfd(fd), cmd, pt.void(arg or 0))
  if ret == -1 then return nil, t.error() end

  if fcntl_ret[cmd] then return fcntl_ret[cmd](ret, arg) end

  return true
end

-- TODO change to type
function S.uname()
  local u = t.utsname()
  local ret = C.uname(u)
  if ret == -1 then return nil, t.error() end
  return {sysname = ffi.string(u.sysname), nodename = ffi.string(u.nodename), release = ffi.string(u.release),
          version = ffi.string(u.version), machine = ffi.string(u.machine), domainname = ffi.string(u.domainname)}
end

function S.gethostname()
  local u, err = S.uname()
  if not u then return nil, err end
  return u.nodename
end

function S.getdomainname()
  local u, err = S.uname()
  if not u then return nil, err end
  return u.domainname
end

function S.sethostname(s) -- only accept Lua string, do not see use case for buffer as well
  return retbool(C.sethostname(s, #s))
end

function S.setdomainname(s)
  return retbool(C.setdomainname(s, #s))
end

-- does not support passing a function as a handler, use sigaction instead
-- actualy glibc does not call the syscall anyway, defines in terms of sigaction; TODO we should too
function S.signal(signum, handler) return retbool(C.signal(c.SIG[signum], c.SIGACT[handler])) end

-- missing siginfo functionality for now, only supports getting signum TODO
-- NOTE I do not think it is safe to call this with a function argument as the jit compiler will not know when it is going to
-- be called, so have removed this functionality again
-- recommend using signalfd to handle signals if you need to do anything complex.
-- note arguments can be different TODO should we change
function S.sigaction(signum, handler, mask, flags)
  local sa
  if ffi.istype(t.sigaction, handler) then sa = handler
  else
    if type(handler) == 'string' then
      handler = ffi.cast(t.sighandler, t.int1(c.SIGACT[handler]))
    --elseif
    --  type(handler) == 'function' then handler = ffi.cast(t.sighandler, handler) -- TODO check if gc problem here? need to copy?
    end
    sa = t.sigaction{sa_handler = handler, sa_mask = t.sigset(mask), sa_flags = c.SA[flags]}
  end
  local old = t.sigaction()
  local ret = C.sigaction(c.SIG[signum], sa, old)
  if ret == -1 then return nil, t.error() end
  return old
end

function S.kill(pid, sig) return retbool(C.kill(pid, c.SIG[sig])) end
function S.killpg(pgrp, sig) return S.kill(-pgrp, sig) end

function S.gettimeofday(tv)
  if not tv then tv = t.timeval() end -- note it is faster to pass your own tv if you call a lot
  local ret = C.gettimeofday(tv, nil)
  if ret == -1 then return nil, t.error() end
  return tv
end

function S.settimeofday(tv) return retbool(C.settimeofday(tv, nil)) end

function S.time(time) return retnum(C.time(time)) end

function S.sysinfo(info)
  if not info then info = t.sysinfo() end
  local ret = C.sysinfo(info)
  if ret == -1 then return nil, t.error() end
  return info
end

local function growattrbuf(f, a, b)
  local len = 512
  local buffer = t.buffer(len)
  local ret
  repeat
    if b then
      ret = f(a, b, buffer, len)
    else
      ret = f(a, buffer, len)
    end
    ret = tonumber(ret)
    if ret == -1 and ffi.errno() ~= c.E.RANGE then return nil, t.error() end
    if ret == -1 then
      len = len * 2
      buffer = t.buffer(len)
    end
  until ret >= 0

  return ffi.string(buffer, ret)
end

local function lattrbuf(sys, a)
  local s, err = growattrbuf(sys, a)
  if not s then return nil, err end
  local tab = split('\0', s)
  tab[#tab] = nil -- there is a trailing \0 so one extra
  return tab
end

function S.listxattr(path) return lattrbuf(C.listxattr, path) end
function S.llistxattr(path) return lattrbuf(C.llistxattr, path) end
function S.flistxattr(fd) return lattrbuf(C.flistxattr, getfd(fd)) end

function S.setxattr(path, name, value, flags)
  return retbool(C.setxattr(path, name, value, #value, c.XATTR[flags]))
end
function S.lsetxattr(path, name, value, flags)
  return retbool(C.lsetxattr(path, name, value, #value, c.XATTR[flags]))
end
function S.fsetxattr(fd, name, value, flags)
  return retbool(C.fsetxattr(getfd(fd), name, value, #value, c.XATTR[flags]))
end

function S.getxattr(path, name) return growattrbuf(C.getxattr, path, name) end
function S.lgetxattr(path, name) return growattrbuf(C.lgetxattr, path, name) end
function S.fgetxattr(fd, name) return growattrbuf(C.fgetxattr, getfd(fd), name) end

function S.removexattr(path, name) return retbool(C.removexattr(path, name)) end
function S.lremovexattr(path, name) return retbool(C.lremovexattr(path, name)) end
function S.fremovexattr(fd, name) return retbool(C.fremovexattr(getfd(fd), name)) end

-- helper function to set and return attributes in tables
local function xattr(list, get, set, remove, path, t)
  local l, err = list(path)
  if not l then return nil, err end
  if not t then -- no table, so read
    local r = {}
    for _, name in ipairs(l) do
      r[name] = get(path, name) -- ignore errors
    end
    return r
  end
  -- write
  for _, name in ipairs(l) do
    if t[name] then
      set(path, name, t[name]) -- ignore errors, replace
      t[name] = nil
    else
      remove(path, name)
    end
  end
  for name, value in pairs(t) do
    set(path, name, value) -- ignore errors, create
  end
  return true
end

function S.xattr(path, t) return xattr(S.listxattr, S.getxattr, S.setxattr, S.removexattr, path, t) end
function S.lxattr(path, t) return xattr(S.llistxattr, S.lgetxattr, S.lsetxattr, S.lremovexattr, path, t) end
function S.fxattr(fd, t) return xattr(S.flistxattr, S.fgetxattr, S.fsetxattr, S.fremovexattr, fd, t) end

-- fdset handlers
local function mkfdset(fds, nfds) -- should probably check fd is within range (1024), or just expand structure size
  local set = t.fdset()
  for i, v in ipairs(fds) do
    local fd = tonumber(getfd(v))
    if fd + 1 > nfds then nfds = fd + 1 end
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    set.fds_bits[fdelt] = bit.bor(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) -- always 32 bit words
  end
  return set, nfds
end

local function fdisset(fds, set)
  local f = {}
  for i, v in ipairs(fds) do
    local fd = tonumber(getfd(v))
    local fdelt = bit.rshift(fd, 5) -- always 32 bits
    if bit.band(set.fds_bits[fdelt], bit.lshift(1, fd % 32)) ~= 0 then table.insert(f, v) end -- careful not to duplicate fd objects
  end
  return f
end

function S.sigprocmask(how, set)
  local oldset = t.sigset()
  local ret = C.sigprocmask(c.SIGPM[how], t.sigset(set), oldset)
  if ret == -1 then return nil, t.error() end
  return oldset
end

function S.sigpending()
  local set = t.sigset()
  local ret = C.sigpending(set)
  if ret == -1 then return nil, t.error() end
 return set
end

function S.sigsuspend(mask) return retbool(C.sigsuspend(t.sigset(mask))) end

function S.signalfd(set, flags, fd) -- note different order of args, as fd usually empty. See also signalfd_read()
  if fd then fd = getfd(fd) else fd = -1 end
  return retfd(C.signalfd(fd, t.sigset(set), c.SFD[flags]))
end

-- TODO convert to metatype. Problem is how to deal with nfds
function S.select(sel) -- note same structure as returned
  local r, w, e
  local nfds = 0
  local timeout
  if sel.timeout then timeout = istype(t.timeval, sel.timeout) or t.timeval(sel.timeout) end
  r, nfds = mkfdset(sel.readfds or {}, nfds or 0)
  w, nfds = mkfdset(sel.writefds or {}, nfds)
  e, nfds = mkfdset(sel.exceptfds or {}, nfds)
  local ret = C.select(nfds, r, w, e, timeout)
  if ret == -1 then return nil, t.error() end
  return {readfds = fdisset(sel.readfds or {}, r), writefds = fdisset(sel.writefds or {}, w),
          exceptfds = fdisset(sel.exceptfds or {}, e), count = tonumber(ret)}
end

function S.pselect(sel) -- note same structure as returned
  local r, w, e
  local nfds = 0
  local timeout, set
  if sel.timeout then
    if ffi.istype(t.timespec, sel.timeout) then timeout = sel.timeout else timeout = t.timespec(sel.timeout) end
  end
  if sel.sigset then set = t.sigset(sel.sigset) end
  r, nfds = mkfdset(sel.readfds or {}, nfds or 0)
  w, nfds = mkfdset(sel.writefds or {}, nfds)
  e, nfds = mkfdset(sel.exceptfds or {}, nfds)
  local ret = C.pselect(nfds, r, w, e, timeout, set)
  if ret == -1 then return nil, t.error() end
  return {readfds = fdisset(sel.readfds or {}, r), writefds = fdisset(sel.writefds or {}, w),
          exceptfds = fdisset(sel.exceptfds or {}, e), count = tonumber(ret), sigset = set}
end

function S.poll(fds, timeout)
  fds = istype(t.pollfds, fds) or t.pollfds(fds)
  local ret = C.poll(fds.pfd, #fds, timeout or -1)
  if ret == -1 then return nil, t.error() end
  return fds
end

-- note that syscall does return timeout remaining but libc does not, due to standard prototype
function S.ppoll(fds, timeout, set)
  fds = istype(t.pollfds, fds) or t.pollfds(fds)
  if timeout then timeout = istype(t.timespec, timeout) or t.timespec(timeout) end
  if set then set = t.sigset(set) end
  local ret = C.ppoll(fds.pfd, #fds, timeout, set)
  if ret == -1 then return nil, t.error() end
  return fds
end

function S.mount(source, target, filesystemtype, mountflags, data)
  if type(source) == "table" then
    local t = source
    source = t.source
    target = t.target
    filesystemtype = t.type
    mountflags = t.flags
    data = t.data
  end
  return retbool(C.mount(source, target, filesystemtype, c.MS[mountflags], data))
end

function S.umount(target, flags)
  return retbool(C.umount2(target, c.UMOUNT[flags]))
end

-- unlimited value. TODO metatype should return this to Lua.
-- TODO math.huge should be converted to this in __new
-- TODO move to constants?
S.RLIM_INFINITY = ffi.cast("rlim64_t", -1)

function S.prlimit(pid, resource, new_limit, old_limit)
  if new_limit then new_limit = istype(t.rlimit, new_limit) or t.rlimit(new_limit) end
  old_limit = old_limit or t.rlimit()
  local ret = C.prlimit64(pid or 0, c.RLIMIT[resource], new_limit, old_limit)
  if ret == -1 then return nil, t.error() end
  return old_limit
end

-- old rlimit functions are 32 bit only so now defined using prlimit
function S.getrlimit(resource)
  return S.prlimit(0, resource)
end

function S.setrlimit(resource, rlim)
  local ret, err = S.prlimit(0, resource, rlim)
  if not ret then return nil, err end
  return true
end

function S.epoll_create(flags)
  return retfd(C.epoll_create1(c.EPOLLCREATE[flags]))
end

function S.epoll_ctl(epfd, op, fd, event, data)
  if not ffi.istype(t.epoll_event, event) then
    local events = c.EPOLL[event]
    event = t.epoll_event()
    event.events = events
    if data then event.data.u64 = data else event.data.fd = getfd(fd) end
  end
  return retbool(C.epoll_ctl(getfd(epfd), c.EPOLL_CTL[op], getfd(fd), event))
end

function S.epoll_wait(epfd, events, maxevents, timeout)
  maxevents = maxevents or 16
  events = events or t.epoll_events(maxevents)
  local ret = C.epoll_wait(getfd(epfd), events, maxevents, timeout or -1)
  if ret == -1 then return nil, t.error() end
  return t.epoll_wait(ret, events)
end

function S.epoll_pwait(epfd, events, maxevents, timeout, sigmask)
  maxevents = maxevents or 16
  events = events or t.epoll_events(maxevents)
  if sigmask then sigmask = istype(t.sigset, sigmask) or t.sigset(sigmask) end
  local ret = C.epoll_pwait(getfd(epfd), events, maxevents, timeout or -1, sigmask)
  if ret == -1 then return nil, t.error() end
  return t.epoll_wait(ret, events)
end

function S.splice(fd_in, off_in, fd_out, off_out, len, flags)
  local offin, offout = off_in, off_out
  if off_in and not ffi.istype(t.loff1, off_in) then
    offin = t.loff1()
    offin[0] = off_in
  end
  if off_out and not ffi.istype(t.loff1, off_out) then
    offout = t.loff1()
    offout[0] = off_out
  end
  return retnum(C.splice(getfd(fd_in), offin, getfd(fd_out), offout, len, c.SPLICE_F[flags]))
end

function S.vmsplice(fd, iov, flags)
  iov = istype(t.iovecs, iov) or t.iovecs(iov)
  return retnum(C.vmsplice(getfd(fd), iov.iov, #iov, c.SPLICE_F[flags]))
end

function S.tee(fd_in, fd_out, len, flags)
  return retnum(C.tee(getfd(fd_in), getfd(fd_out), len, c.SPLICE_F[flags]))
end

function S.inotify_init(flags) return retfd(C.inotify_init1(c.IN_INIT[flags])) end
function S.inotify_add_watch(fd, pathname, mask) return retnum(C.inotify_add_watch(getfd(fd), pathname, c.IN[mask])) end
function S.inotify_rm_watch(fd, wd) return retbool(C.inotify_rm_watch(getfd(fd), wd)) end

-- helper function to read inotify structs as table from inotify fd
function S.inotify_read(fd, buffer, len)
  len = len or 1024
  buffer = buffer or t.buffer(len)
  local ret, err = S.read(fd, buffer, len)
  if not ret then return nil, err end
  return t.inotify_events(buffer, ret)
end

function S.sendfile(out_fd, in_fd, offset, count) -- bit odd having two different return types...
  if not offset then return retnum(C.sendfile(getfd(out_fd), getfd(in_fd), nil, count)) end
  local off = t.off1()
  off[0] = offset
  local ret = C.sendfile(getfd(out_fd), getfd(in_fd), off, count)
  if ret == -1 then return nil, t.error() end
  return {count = tonumber(ret), offset = tonumber(off[0])}
end

function S.eventfd(initval, flags) return retfd(C.eventfd(initval or 0, c.EFD[flags])) end

function S.getitimer(which, value)
  if not value then value = t.itimerval() end
  local ret = C.getitimer(c.ITIMER[which], value)
  if ret == -1 then return nil, t.error() end
  return value
end

function S.setitimer(which, it)
  it = istype(t.itimerval, it) or t.itimerval(it)
  local oldtime = t.itimerval()
  local ret = C.setitimer(c.ITIMER[which], it, oldtime)
  if ret == -1 then return nil, t.error() end
  return oldtime
end

function S.timerfd_create(clockid, flags)
  return retfd(C.timerfd_create(c.CLOCK[clockid], c.TFD[flags]))
end

function S.timerfd_settime(fd, flags, it, oldtime)
  oldtime = oldtime or t.itimerspec()
  it = istype(t.itimerspec, it) or t.itimerspec(it)
  local ret = C.timerfd_settime(getfd(fd), c.TFD_TIMER[flags], it, oldtime)
  if ret == -1 then return nil, t.error() end
  return oldtime
end

function S.timerfd_gettime(fd, curr_value)
  if not curr_value then curr_value = t.itimerspec() end
  local ret = C.timerfd_gettime(getfd(fd), curr_value)
  if ret == -1 then return nil, t.error() end
  return curr_value
end

function S.pivot_root(new_root, put_old) return retbool(C.pivot_root(new_root, put_old)) end

-- aio functions
function S.io_setup(nr_events)
  local ctx = t.aio_context1()
  local ret = C.io_setup(nr_events, ctx)
  if ret == -1 then return nil, t.error() end
  return ctx[0]
end

function S.io_destroy(ctx) return retbool(C.io_destroy(ctx)) end

function S.io_cancel(ctx, iocb, result)
  if not result then result = t.io_event() end
  local ret = C.io_cancel(ctx, iocb, result)
  if ret == -1 then return nil, t.error() end
  return result
end

function S.io_getevents(ctx, min, nr, events, timeout)
  events = events or t.io_events(nr)
  if timeout then timeout = istype(t.timespec, timeout) or t.timespec(timeout) end -- nil ok
  local ret = C.io_getevents(ctx, min, nr, events, timeout)
  if ret == -1 then return nil, t.error() end
  -- TODO convert to metatype for io_event
  -- TODO metatype should support error type if res is negative
  local r = {}
  for i = 0, ret - 1 do
    r[i + 1] = events[i]
  end
  r.timeout = timeout
  r.events = events
  r.count = tonumber(ret)
  return r
end

-- TODO this is broken as iocb must persist until retrieved, and could be gc'd if passed as table...
function S.io_submit(ctx, iocb) -- takes a t.iocb_array in order to pin for gc
  return retnum(C.io_submit(ctx, iocb.ptrs, iocb.nr))
end

-- map for valid options for arg2
local prctlmap = {
  [c.PR.CAPBSET_READ] = c.CAP,
  [c.PR.CAPBSET_DROP] = c.CAP,
  [c.PR.SET_ENDIAN] = c.PR_ENDIAN,
  [c.PR.SET_FPEMU] = c.PR_FPEMU,
  [c.PR.SET_FPEXC] = c.PR_FP_EXC,
  [c.PR.SET_PDEATHSIG] = c.SIG,
  --[c.PR.SET_SECUREBITS] = c.SECBIT, -- TODO not defined yet
  [c.PR.SET_TIMING] = c.PR_TIMING,
  [c.PR.SET_TSC] = c.PR_TSC,
  [c.PR.SET_UNALIGN] = c.PR_UNALIGN,
  [c.PR.MCE_KILL] = c.PR_MCE_KILL,
  [c.PR.SET_SECCOMP] = c.SECCOMP_MODE,
  [c.PR.SET_NO_NEW_PRIVS] = c.BOOLEAN,
}

local prctlrint = { -- returns an integer directly TODO add metatables to set names
  [c.PR.GET_DUMPABLE] = true,
  [c.PR.GET_KEEPCAPS] = true,
  [c.PR.CAPBSET_READ] = true,
  [c.PR.GET_TIMING] = true,
  [c.PR.GET_SECUREBITS] = true,
  [c.PR.MCE_KILL_GET] = true,
  [c.PR.GET_SECCOMP] = true,
}

local prctlbool = {
  [c.PR.GET_NO_NEW_PRIVS] = true,
}

local prctlpint = { -- returns result in a location pointed to by arg2
  [c.PR.GET_ENDIAN] = true,
  [c.PR.GET_FPEMU] = true,
  [c.PR.GET_FPEXC] = true,
  [c.PR.GET_PDEATHSIG] = true,
  [c.PR.GET_UNALIGN] = true,
}

-- this is messy, TODO clean up
function S.prctl(option, arg2, arg3, arg4, arg5)
  local i, name
  option = c.PR[option]
  local m = prctlmap[option]
  if m then arg2 = m[arg2] end
  if option == c.PR.MCE_KILL and arg2 == c.PR.MCE_KILL_SET then arg3 = c.PR_MCE_KILL_OPT[arg3]
  elseif prctlpint[option] then
    i = t.int1()
    arg2 = ffi.cast(t.ulong, i)
  elseif option == c.PR.GET_NAME then
    name = t.buffer(16)
    arg2 = ffi.cast(t.ulong, name)
  elseif option == c.PR.SET_NAME then
    if type(arg2) == "string" then arg2 = ffi.cast(t.ulong, arg2) end
  elseif option == c.PR.SET_SECCOMP then
    arg3 = tonumber(ffi.cast(t.intptr, arg3 or 0))
  end
  local ret = C.prctl(option, arg2 or 0, arg3 or 0, arg4 or 0, arg5 or 0)
  if ret == -1 then return nil, t.error() end
  if prctlrint[option] then return ret end
  if prctlpint[option] then return i[0] end
  if prctlbool[option] then return ret == 1 end
  if option == c.PR.GET_NAME then
    if name[15] ~= 0 then return ffi.string(name, 16) end -- actually, 15 bytes seems to be longest, aways 0 terminated
    return ffi.string(name)
  end
  return true
end

-- this is the glibc name for the syslog syscall
function S.klogctl(tp, buf, len)
  if not buf and (tp == 2 or tp == 3 or tp == 4) then
    if not len then
      len = C.klogctl(10, nil, 0) -- get size so we can allocate buffer
      if len == -1 then return nil, t.error() end
    end
    buf = t.buffer(len)
  end
  local ret = C.klogctl(tp, buf or nil, len or 0)
  if ret == -1 then return nil, t.error() end
  if tp == 9 or tp == 10 then return tonumber(ret) end
  if tp == 2 or tp == 3 or tp == 4 then return ffi.string(buf, ret) end
  return true
end

function S.adjtimex(a)
  a = istype(t.timex, a) or t.timex(a)
  local ret = C.adjtimex(a)
  if ret == -1 then return nil, t.error() end
  return t.adjtimex(ret, a)
end

function S.clock_getres(clk_id, ts)
  ts = istype(t.timespec, ts) or t.timespec(ts)
  local ret = C.clock_getres(c.CLOCK[clk_id], ts)
  if ret == -1 then return nil, t.error() end
  return ts
end

function S.clock_gettime(clk_id, ts)
  ts = istype(t.timespec, ts) or t.timespec(ts)
  local ret = C.clock_gettime(c.CLOCK[clk_id], ts)
  if ret == -1 then return nil, t.error() end
  return ts
end

function S.clock_settime(clk_id, ts)
  ts = istype(t.timespec, ts) or t.timespec(ts)
  return retbool(C.clock_settime(c.CLOCK[clk_id], ts))
end

function S.clock_nanosleep(clk_id, flags, req, rem)
  req = istype(t.timespec, req) or t.timespec(req)
  rem = rem or t.timespec()
  local ret = C.clock_nanosleep(c.CLOCK[clk_id], c.TIMER[flags], req, rem)
  if ret == -1 then
    if ffi.errno() == c.E.INTR then return rem else return nil, t.error() end
  end
  return true
end

-- straight passthroughs, no failure possible, still wrap to allow mocking
function S.getuid() return C.getuid() end
function S.geteuid() return C.geteuid() end
function S.getppid() return C.getppid() end
function S.getgid() return C.getgid() end
function S.getegid() return C.getegid() end
function S.sync() return C.sync() end
function S.alarm(s) return C.alarm(s) end

function S.getpid() return C.getpid() end -- note this will use syscall as overridden above

function S.setuid(uid) return retbool(C.setuid(uid)) end
function S.setgid(gid) return retbool(C.setgid(gid)) end
function S.seteuid(uid) return retbool(C.seteuid(uid)) end
function S.setegid(gid) return retbool(C.setegid(gid)) end
function S.setreuid(ruid, euid) return retbool(C.setreuid(ruid, euid)) end
function S.setregid(rgid, egid) return retbool(C.setregid(rgid, egid)) end

function S.getresuid()
  local ruid, euid, suid = t.uid1(), t.uid1(), t.uid1()
  local ret = C.getresuid(ruid, euid, suid)
  if ret == -1 then return nil, t.error() end
  return {ruid = ruid[0], euid = euid[0], suid = suid[0]}
end
function S.getresgid()
  local rgid, egid, sgid = t.gid1(), t.gid1(), t.gid1()
  local ret = C.getresgid(rgid, egid, sgid)
  if ret == -1 then return nil, t.error() end
  return {rgid = rgid[0], egid = egid[0], sgid = sgid[0]}
end
function S.setresuid(ruid, euid, suid)
  if type(ruid) == "table" then
    local t = ruid
    ruid = t.ruid
    euid = t.euid
    suid = t.suid
  end
  return retbool(C.setresuid(ruid, euid, suid))
end
function S.setresgid(rgid, egid, sgid)
  if type(rgid) == "table" then
    local t = rgid
    rgid = t.rgid
    egid = t.egid
    sgid = t.sgid
  end
  return retbool(C.setresgid(rgid, egid, sgid))
end

function S.getgroups()
  local size = C.getgroups(0, nil)
  if size == -1 then return nil, t.error() end
  local groups = t.groups(size)
  local ret = C.getgroups(size, groups.list)
  if ret == -1 then return nil, t.error() end
  return groups
end

function S.setgroups(groups)
  if type(groups) == "table" then groups = t.groups(groups) end
  return retbool(C.setgroups(groups.count, groups.list))
end

function S.umask(mask) return C.umask(c.MODE[mask]) end

function S.getsid(pid) return retnum(C.getsid(pid or 0)) end
function S.setsid() return retnum(C.setsid()) end

function S.vhangup() return retbool(C.vhangup()) end

function S.swapon(path, swapflags) return retbool(C.swapon(path, c.SWAP_FLAG[swapflags])) end
function S.swapoff(path) return retbool(C.swapoff(path)) end

-- capabilities. Somewhat complex kernel interface due to versioning, Posix requiring malloc in API.
-- only support version 3, should be ok for recent kernels, or pass your own hdr, data in
-- to detect capability API version, pass in hdr with empty version, version will be set
function S.capget(hdr, data) -- normally just leave as nil for get, can pass pid in
  hdr = istype(t.user_cap_header, hdr) or t.user_cap_header(c.LINUX_CAPABILITY_VERSION[3], hdr or 0)
  if not data and hdr.version ~= 0 then data = t.user_cap_data2() end
  local ret = C.capget(hdr, data)
  if ret == -1 then return nil, t.error() end
  if not data then return hdr end
  return t.capabilities(hdr, data)
end

function S.capset(hdr, data)
  if ffi.istype(t.capabilities, hdr) then hdr, data = hdr.hdrdata() end
  return retbool(C.capset(hdr, data))
end

-- 'macros' and helper functions etc
-- TODO from here (approx, some may be in wrong place), move to syscall.util library.

-- handle environment (Lua only provides os.getenv). TODO add metatable to make more Lualike.
function S.environ() -- return whole environment as table
  local environ = ffi.C.environ
  if not environ then return nil end
  local r = {}
  local i = 0
  while environ[i] ~= zeropointer do
    local e = ffi.string(environ[i])
    local eq = e:find('=')
    if eq then
      r[e:sub(1, eq - 1)] = e:sub(eq + 1)
    end
    i = i + 1
  end
  return r
end

function S.getenv(name)
  return S.environ()[name]
end
function S.unsetenv(name) return retbool(C.unsetenv(name)) end
function S.setenv(name, value, overwrite)
  if type(overwrite) == 'boolean' and overwrite then overwrite = 1 end
  return retbool(C.setenv(name, value, overwrite or 0))
end
function S.clearenv() return retbool(C.clearenv()) end

function S.nonblock(fd)
  local fl, err = S.fcntl(fd, c.F.GETFL)
  if not fl then return nil, err end
  fl, err = S.fcntl(fd, c.F.SETFL, bit.bor(fl, c.O.NONBLOCK))
  if not fl then return nil, err end
  return true
end

function S.block(fd)
  local fl, err = S.fcntl(fd, c.F.GETFL)
  if not fl then return nil, err end
  fl, err = S.fcntl(fd, c.F.SETFL, bit.band(fl, bit.bnot(c.O.NONBLOCK)))
  if not fl then return nil, err end
  return true
end

-- Nixio compatibility to make porting easier, and useful functions (often man 3). Incomplete.
function S.setblocking(s, b) if b then return S.block(s) else return S.nonblock(s) end end
function S.tell(fd) return S.lseek(fd, 0, c.SEEK.CUR) end

function S.lockf(fd, cmd, len)
  cmd = c.LOCKF[cmd]
  if cmd == c.LOCKF.LOCK then
    return S.fcntl(fd, c.F.SETLKW, {l_type = c.FCNTL_LOCK.WRLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
  elseif cmd == c.LOCKF.TLOCK then
    return S.fcntl(fd, c.F.SETLK, {l_type = c.FCNTL_LOCK.WRLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
  elseif cmd == c.LOCKF.ULOCK then
    return S.fcntl(fd, c.F.SETLK, {l_type = c.FCNTL_LOCK.UNLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
  elseif cmd == c.LOCKF.TEST then
    local ret, err = S.fcntl(fd, c.F.GETLK, {l_type = c.FCNTL_LOCK.WRLCK, l_whence = c.SEEK.CUR, l_start = 0, l_len = len})
    if not ret then return nil, err end
    return ret.l_type == c.FCNTL_LOCK.UNLCK
  end
end

-- constants TODO move to table
S.INADDR_ANY = t.in_addr()
S.INADDR_LOOPBACK = t.in_addr("127.0.0.1")
S.INADDR_BROADCAST = t.in_addr("255.255.255.255")
-- ipv6 versions
S.in6addr_any = t.in6_addr()
S.in6addr_loopback = t.in6_addr("::1")

-- methods on an fd
-- note could split, so a socket does not have methods only appropriate for a file
local fdmethods = {'nonblock', 'block', 'setblocking', 'sendfds', 'sendcred',
                   'dup', 'read', 'write', 'pread', 'pwrite', 'tell', 'lockf',
                   'lseek', 'fchdir', 'fsync', 'fdatasync', 'fstat', 'fcntl', 'fchmod',
                   'bind', 'listen', 'connect', 'accept', 'getsockname', 'getpeername',
                   'send', 'sendto', 'recv', 'recvfrom', 'readv', 'writev', 'sendmsg',
                   'recvmsg', 'setsockopt', 'epoll_ctl', 'epoll_wait', 'sendfile', 'getdents',
                   'ftruncate', 'shutdown', 'getsockopt',
                   'inotify_add_watch', 'inotify_rm_watch', 'inotify_read', 'flistxattr',
                   'fsetxattr', 'fgetxattr', 'fremovexattr', 'fxattr', 'splice', 'vmsplice', 'tee',
                   'timerfd_gettime', 'timerfd_settime',
                   'fadvise', 'fallocate', 'posix_fallocate', 'readahead',
                   'sync_file_range', 'fstatfs', 'futimens',
                   'fstatat', 'unlinkat', 'mkdirat', 'mknodat', 'faccessat', 'fchmodat', 'fchown',
                   'fchownat', 'readlinkat', 'setns', 'openat',
                   'preadv', 'pwritev', "epoll_pwait"
                   }
local fmeth = {}
for _, v in ipairs(fdmethods) do fmeth[v] = S[v] end

-- allow calling without leading f
fmeth.stat = S.fstat
fmeth.chdir = S.fchdir
fmeth.sync = S.fsync
fmeth.datasync = S.fdatasync
fmeth.chmod = S.fchmod
fmeth.setxattr = S.fsetxattr
fmeth.getxattr = S.gsetxattr
fmeth.truncate = S.ftruncate
fmeth.statfs = S.fstatfs
fmeth.utimens = S.futimens
fmeth.utime = S.futimens
fmeth.seek = S.lseek
fmeth.lock = S.lockf
fmeth.chown = S.fchown

local function nogc(d) return ffi.gc(d, nil) end

fmeth.nogc = nogc

-- sequence number used by netlink messages
fmeth.seq = function(fd)
  fd.sequence = fd.sequence + 1
  return fd.sequence
end

function fmeth.close(fd)
  local fileno = getfd(fd)
  if fileno == -1 then return true end -- already closed
  local ok, err = S.close(fileno)
  fd.filenum = -1 -- make sure cannot accidentally close this fd object again
  return ok, err
end

fmeth.getfd = function(fd) return fd.filenum end

t.fd = ffi.metatype("struct {int filenum; int sequence;}", {
  __index = fmeth,
  __gc = fmeth.close,
  __new = function(tp, i)
    return istype(tp, i) or ffi.new(tp, i)
  end
})

-- override socketpair to provide methods
local mt_socketpair = {
  __index = {
    close = function(s)
      local ok1, err1 = s[1]:close()
      local ok2, err2 = s[2]:close()
      if not ok1 then return nil, err1 end
      if not ok2 then return nil, err2 end
      return true
    end,
    nonblock = function(s)
      local ok, err = S.nonblock(s[1])
      if not ok then return nil, err end
      local ok, err = S.nonblock(s[2])
      if not ok then return nil, err end
      return true
    end,
    block = function(s)
      local ok, err = S.block(s[1])
      if not ok then return nil, err end
      local ok, err = S.block(s[2])
      if not ok then return nil, err end
      return true
    end,
    setblocking = function(s, b)
      local ok, err = S.setblocking(s[1], b)
      if not ok then return nil, err end
      local ok, err = S.setblocking(s[2], b)
      if not ok then return nil, err end
      return true
    end,
  }
}

t.socketpair = function(s1, s2)
  if ffi.istype(t.int2, s1) then s1, s2 = s1[0], s1[1] end
  return setmetatable({t.fd(s1), t.fd(s2)}, mt_socketpair)
end

-- override pipe to provide methods
local mt_pipe = {
  __index = {
    close = function(p)
      local ok1, err1 = p[1]:close()
      local ok2, err2 = p[2]:close()
      if not ok1 then return nil, err1 end
      if not ok2 then return nil, err2 end
      return true
    end,
    read = function(p, ...) return S.read(p[1], ...) end,
    write = function(p, ...) return S.write(p[2], ...) end,
    nonblock = function(p)
      local ok, err = p[1]:nonblock()
      if not ok then return nil, err end
      local ok, err = p[2]:nonblock()
      if not ok then return nil, err end
      return true
    end,
    block = function(p)
      local ok, err = p[1]:block()
      if not ok then return nil, err end
      local ok, err = p[2]:block()
      if not ok then return nil, err end
      return true
    end,
    setblocking = function(p, b)
      local ok, err = p[1]:setblocking(b)
      if not ok then return nil, err end
      local ok, err = p[2]:setblocking(b)
      if not ok then return nil, err end
      return true
    end,
    -- TODO many useful methods still missing
  }
}

t.pipe = function(s1, s2)
  if ffi.istype(t.int2, s1) then s1, s2 = s1[0], s1[1] end
  return setmetatable({t.fd(s1), t.fd(s2)}, mt_pipe)
end

S.stdin = t.fd(c.STD.IN):nogc()
S.stdout = t.fd(c.STD.OUT):nogc()
S.stderr = t.fd(c.STD.ERR):nogc()

-- TODO reinstate this, more like fd is, hence changes to destroy
--[[
t.aio_context = ffi.metatype("struct {aio_context_t ctx;}", {
  __index = {destroy = S.io_destroy, submit = S.io_submit, getevents = S.io_getevents, cancel = S.io_cancel, nogc = nogc},
  __gc = S.io_destroy
})
]]

return S

