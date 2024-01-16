## /proc 目录结构
- `/proc/apm` : 文件，apm即Advanced Power Management，需要配置CONFIG_APM。
- `/proc/buddyinfo` : 文件，用于诊断内存碎片问题。
- `/proc/cmdline` : 文件，系统启动时传递给Linux内核的参数，如lilo、grub等boot管理模块。
- `/proc/config.gz` : 文件，内核编译配置选项，需要配置CONFIG_IKCONFIG_PROC。
- `/proc/crypto` : 文件，内核加密API提供的加密列表。
- `/proc/cpuinfo` : 文件，CPU和系统架构信息，lscpu命令使用这个文件。
- `/proc/devices` : 文件，设备相关信息。
- `/proc/diskstats` : 文件，磁盘状态。
- `/proc/dma` : 文件，dma即Direct Memory Access。
- `/proc/driver/rtc` : 文件，系统运行时配置。
- `/proc/execdomains` : 文件，执行域列表。
- `/proc/fb` : 文件，Frame Buffer信息，需要配置CONFIG_FB。
- `/proc/filesystems` : 文件，内核支持的文件系统类型（man filesystems）。
- `/proc/fs` : 目录，挂载的文件系统信息。
- `/proc/ide` : 目录，用于IDE接口。
- `/proc/interrupts` : 文件，每个CPU每个IO的中断信息。
- `/proc/iomem` : 文件，IO内存映射信息。
- `/proc/ioports` : 文件，IO端口信息。
- `/proc/kallsyms` : 文件，用于动态链接和和模块绑定的符号定义。
- `/proc/kcore` : 文件，系统中ELF格式的物理内存。
- `/proc/kmsg` : 文件，内核信息，dmsg命令使用这个文件。
- `/proc/kpagecount` : 文件，每个物理页帧映射的次数，需要配置CONFIG_PROC_PAGE_MONITOR。
- `/proc/kpageflags` : 文件，每个物理页帧的掩码，需要配置CONFIG_PROC_PAGE_MONITOR。
- `/proc/ksyms` : 文件，同kallsyms。
- `/proc/loadavg` : 文件，工作负荷。
- `/proc/locks` : 文件，当前文件锁的状态。
- `/proc/malloc` : 文件，需要配置CONFIG_DEBUG_MALLOC。
- `/proc/meminfo` : 文件，系统内存使用统计，free命令使用了这个文件。
- `/proc/modules` : 文件，系统加载的模块信息，相关命令为lsmod。
- `/proc/mounts` : 文件，链接到了/self/mounts。
- `/proc/mtrr` : 文件，Memory Type Range Registers。
- `/proc/partitions` : 文件，分区信息。
- `/proc/pci` : 文件，PCI接口设备。
- `/proc/profile` : 文件，用于readprofile命令作性能分析。
- `/proc/scsi` : 目录，SCSI接口设备。
- `/proc/scsi/scsi`
- `/proc/scsi/[drivername]`
- `/proc/self` : 目录，链接到了当前进程所在的目录。
- `/proc/slabinfo` : 文件，内核缓存信息，需要配置CONFIG_SLAB。
- `/proc/stat` : 文件，系统信息统计。
- `/proc/swaps` : 文件，使用的交换空间。
- `/proc/sysrq` : -trigger，文件，可写，触发系统调用。
- `/proc/sysvipc` : 目录，包括msg、sem、shm三个文件，为System V IPC对象。
- `/proc/thread` : -self，文件，链接到了当前进程下的task目录中的线程文件。
- `/proc/timer_list` : 文件，还在运行着的定时器列表。
- `/proc/timer_stats` : 文件，定时器状态。
- `/proc/tty` : 目录，tty设备相关。
- `/proc/uptime` : 文件，系统更新时间和进程空闲时间。
- `/proc/version` : 文件，内核版本信息。
- `/proc/vmstat` : 文件，内存统计信息，以键值对形式显示。
- `/proc/zoneinfo` : 文件，内存区块信息，用于分析虚拟内存的行为。

## /proc/stat 文件
首先是cpu相关行
> cpu  27210702 200 2113678 1164675143 127535 0 38871 0 0 0
> 
> cpu0 3274710 3 236403 145811635 8461 0 5312 0 0 0

cpu行 参数 解释

- `user` (27210702) 从系统启动开始累计到当前时刻，用户态的CPU时间（单位：jiffies） ，不包含 nice值为负进程。1jiffies=0.01秒
- `nice` (200) 从系统启动开始累计到当前时刻，nice值为负的进程所占用的CPU时间（单位：jiffies）
- `system` (2113678) 从系统启动开始累计到当前时刻，核心时间（单位：jiffies）
- `idle` (1164675143) 从系统启动开始累计到当前时刻，除硬盘IO等待时间以外其它等待时间（单位：jiffies）
- `iowait` (127535) 从系统启动开始累计到当前时刻，硬盘IO等待时间（单位：jiffies） ，
- `irq` (0) 从系统启动开始累计到当前时刻，硬中断时间（单位：jiffies）
- `softirq` (38871) 从系统启动开始累计到当前时刻，软中断时间（单位：jiffies）

CPU时间=user+system+nice+idle+iowait+irq+softirq

- `intr`: 这行给出中断的信息，第一个为自系统启动以来，发生的所有的中断的次数；然后每个数对应一个特定的中断自系统启动以来所发生的次数。
- `ctxt`: 给出了自系统启动以来CPU发生的上下文交换的次数。
- `btime`: 给出了从系统启动到现在为止的时间，单位为秒。
- `processes`: (total_forks) 自系统启动以来所创建的任务的个数目。
- `procs_running`: 当前运行队列的任务的数目。
- `procs_blocked`: 当前被阻塞的任务的数目。

那么CPU利用率可以使用以下两个方法。先取两个采样点，然后计算其差值：

cpu usage=(idle2-idle1)/(cpu2-cpu1)*100

cpu usage=[(user_2 +sys_2+nice_2) - (user_1 + sys_1+nice_1)]/(total_2 - total_1)*100

## /proc/[PID] 进程的目录
- `attr`:   目录，提供了安全相关的属性，可读可写，以支持安全模块如SELinux等，需配置CONFIG_SECURITY。
- `attr/current`:   文件，当前的安全相关的属性。
- `attr/exec`:   文件，执行命令`execve`时设置的安全相关的属性。
- `attr/fscreate`:   文件，文件，执行命令`open`、`mkdir`、`symlink`、`mknod`时设置的安全相关的属性。
- `attr/keycreate`:   文件，执行命令`add_key`时设置的安全相关的属性。
- `attr/prev`:   文件，最后一次执行命令`execve`时的安全相关的属性，即前一个“/proc/[pid]/attr/current”。
- `attr/sockcreate`:   文件，创建socket时设置的安全相关的属性。
- `auxv`:  文件，ELF解释器信息，格式为一个unsigned long类型的ID加一个unsigned long类型的值，最后为两个0（man getauxval）。
- `cgroup`:   文件，进程所属的控制组，格式为冒号分隔的三个字段，分别是结构ID、子系统、控制组，需配置CONFIG_CGROUPS。
- `clear_refs`:   文件，只写，只用于进程的拥有者，清除用于估算内存使用量的PG_Referenced和ACCESSED/YOUNG，有1、2、3、4四种策略，1表示清除相关的所有页，2表示清除相关的匿名页，3表示清除相关的映射文件的页，4表示清除相关的soft-dirty的页，需配置CONFIG_PROC_PAGE_MONITOR。
- `cmdline`:   文件，只读，保存启动进程的完整的命令行字符串，如果是僵尸进程，这个文件为空。
- `comm`:   文件，进程的命令名，不同的线程（man clone prctl pthread_setname_np）可能有不同的线程名，位置在“task/[tid]/comm”，名字长度超过TASK_COMM_LEN时会被截断。
- `coredump_filter`:   文件，coredump过滤器，如00000033（man core），不同的二进制位表示过滤不同的信息。
- `cpuset`:   文件，控制CPU和内存的节点（man cpuset）。
- `cwd`:   目录，符号链接到当前工作目录。
- `environ`:   文件，环境变量。
- `fd`:   目录，包含当前的fd，这些fd符号链接到真正打开的文件。
- `fdinfo`:  目录，包含当前fd的信息，不同类型的fd信息不同。
- `io`:   文件，IO信息。
- `gid_map`:   文件，从用户命名空间映射的组ID的信息（man user_namespaces）。
- `limits`:   文件，资源软、硬限制（man getrlimit）。
- `map_files`:   目录，包括一些内存映射文件（man mmap），文件名格式为BeginAddress-EndAddress，符号链接到映射的文件，需要配置CONFIG_CHECKPOINT_RESTORE。
- `maps`:   文件，内存映射信息，下面“proc-pid-maps”详细介绍。
- `mem`:   文件，用于通过open、read、lseek访问进程的内存页。
- `mountinfo`:   文件，挂载信息，格式为`36 35 98:0 /mnt1 /mnt2 rw,noatime master:1 - ext3 /dev/root rw,errors=continue`，以空格作为分隔符，从左到右各字段的意思分别是唯一挂载ID、父挂载ID、文件系统的设备主从号码、文件系统中挂载的根节点、相对于进程根节点的挂载点、挂载权限等挂载配置、可选配置、短横线表示前面可选配置的结束、文件系统类型、文件系统特有的挂载源或者为none、额外配置。
- `mounts`:   文件，挂载在当前进程的文件系统列表，格式参照（man fstab）。
- `mountstats`:   文件，挂载信息，格式形如`device /dev/sda7 mounted on /home with fstype ext3 [statistics]`。
- `ns`:   目录，保存了每个名字空间的入口，详见（man namespaces）。
- `numa_maps`:   文件，numa即Non Uniform Memory Access，详见（man numa）。
- `oom_adj`:   文件，调整OOM分数，OOM即Out Of Memory，发生OOM时OOM Killer根据OOM分数杀掉分数高的进程，默认值为0，会继承自父进程的设置。
- `oom_score`:   文件，OOM分数。
- `oom_score_adj`:   文件，OOM分值介于-1000到1000之间。
- `pagemap`:   文件，当前进程的虚拟内存页映射信息，需要配置CONFIG_PROC_PAGE_MONITOR。
- `personality`:   文件，进行执行域。
- `root`:   目录，链接到了当前进程的根目录。
- `seccomp`:   文件，seccomp模式下允许的系统调用只有read、write、_exit、sigreturn，Linux 2.6.23已弃用这个文件，由prctl替代。
- `setgroups`:   文件，详见（man user_namespaces）。
- `smaps`:   文件，内存映射信息，类似于pmap命令，需要配置CONFIG_PROC_PAGE_MONITOR，下面“proc-pid-smaps”详细介绍。
- `stack`:   文件，内核空间的函数调用堆栈，需要配置CONFIG_STACKTRACE。
- `stat`:   文件，进程状态信息，用于ps命令。
- `statm`:   文件，进程内存使用信息，以空格分隔的7个数字，从左到右分别表示程序总大小、常驻内存大小、共享内存页大小、text code、library、data + stack、dirty pages。
- `status`:   文件，可读性好的进程相关信息，下面“proc-pid-status”详细介绍。
- `syscall`:   文件，系统调用相关信息，需要配置CONFIG_HAVE_ARCH_TRACEHOOK。
- `task`:  目录，每个线程一个子目录，目录名为线程ID。
- `timers`:   文件，POSIT定时器列表，包括定时器ID、信号等信息。
- `uid_map`:   文件，用户ID映射信息，详见（man user_namespaces）。
- `gid_map`:   文件，组ID映射信息，详见（man user_namespaces）。
- `wchan`:  文件，进程休眠时内核中相应位置的符号表示，如do_wait。


## /proc/[PID]/stat 进程的状态文件

> IFS=" " read -r pid comm state ppid pgrp session tty_nr tpgid flags minflt cminflt \
majflt cmajflt utime stime cutime cstime priority nice num_threads itrealvalue \
starttime vsize rss rsslim startcode endcode startstack kstkesp kstkeip signal \
blocked sigignore sigcatch wchan nswap cnswap exit_signal processor rt_priority \
policy delayacct_blkio_ticks guest_time cguest_time < "/proc/${process_id}/stat"

这段代码是用于从 `/proc/${process_id}/stat` 文件中读取进程信息，并将其分配给一系列变量。下面是对每个变量的详细解释：

- `pid`: 进程ID（Process ID） 进程 (包括轻量级进程，即线程) 号
- `comm`: 进程的命令行名称（Command name）
- `state`: 进程状态（Process state），如正在运行（R），等待（S）、睡眠（D）、僵尸（Z）等
- `ppid`: 父进程ID（Parent Process ID）
- `pgrp`: 进程组ID（Process Group ID）
- `session`: 会话ID（Session ID）
- `tty_nr`: 进程所属的终端设备号（Controlling terminal）
- `tpgid`: 前台进程组ID（Foreground process group ID） 终端的进程组号，当前运行在该任务所在终端的前台任务 (包括 shell 应用程序) 的 PID。
- `flags`: 进程标志位（Flags）查看该任务的特性
- `minflt`: 未分页的次缺页错误数（Number of minor faults） 该任务不需要从硬盘拷数据而发生的缺页（次缺页）的次数
- `cminflt`: 子进程的未分页的次缺页错误数（Number of minor faults with child's） 累计的该任务的所有的 waited-for 进程曾经发生的次缺页的次数目
- `majflt`: 未分页的主缺页错误数（Number of major faults） 该任务需要从硬盘拷数据而发生的缺页（主缺页）的次数
- `cmajflt`: 子进程的未分页的主缺页错误数（Number of major faults with child's） 	累计的该任务的所有的 waited-for 进程曾经发生的主缺页的次数目
- `utime`: 进程用户态使用CPU的时间（User time） 单位为 jiffies
- `stime`: 进程内核态使用CPU的时间（System time） 单位为 jiffies
- `cutime`: 子进程用户态使用CPU的时间（User time of child processes） 单位为 jiffies
- `cstime`: 子进程内核态使用CPU的时间（System time of child processes） 单位为 jiffies
- `priority`: 进程优先级（Priority）
- `nice`: 进程优先级的修正值（The nice value） 	任务的静态优先级
- `num_threads`: 线程数（Number of threads）
- `itrealvalue`: 定时器实现的下一个值（Time in jiffies before the timer should expire）由于计时间隔导致的下一个 SIGALRM 发送进程的时延，以 jiffy 为单位.
- `starttime`: 进程开始时间（Start time of the process） 单位为 jiffies
- `vsize`: 进程虚拟内存大小（Virtual memory size） 单位为 page
- `rss`: 进程的常驻内存集大小（Resident Set Size） 单位为 page
- `rsslim`: 进程的常驻内存集限制大小（Current soft limit in bytes on the rss of the process） 单位：byte
- `startcode`: 代码段的起始地址（Start address of the code segment）
- `endcode`: 代码段的结束地址（End address of the code segment）
- `startstack`: 栈的开始地址（Start address of the stack）
- `kstkesp`: ESP寄存器指针值（Current value of ESP register）
- `kstkeip`: EIP指针值（Current value of EIP register）
- `signal`: 挂起的信号的位图（The signal bitmap）
- `blocked`: 阻塞的信号的位图（The blocked bitmap）
- `sigignore`: 忽略的信号的位图（The ignored bitmap）
- `sigcatch`: 捕获的信号的位图（The caught bitmap）
- `wchan`: 进程等待的内核函数（Address where process went to sleep）
- `nswap`: 从平台启动开始到现在，虚拟内存被换出次数（Number of pages swapped）
- `cnswap`: 子进程从平台启动开始到现在，虚拟内存被换出次数（Number of pages swapped with child's）
- `exit_signal`: 进程终止的信号（Signal to be sent to parent when we die）
- `processor`: 进程正在运行的CPU编号（CPU number last executed on）
- `rt_priority`: 实时优先级（Real-time priority）
- `policy`: 进程调度策略（Scheduling policy） 进程的调度策略，0 = 非实时进程，1=FIFO 实时进程；2=RR 实时进程
- `delayacct_blkio_ticks`: 块IO延迟（Aggregated block I/O delays） 	聚合块 I/O 延迟，以时钟周期（厘秒，百分之一秒）为单位。
- `guest_time`: 宿主操作系统运行虚拟处理器的时间（Guest time of the task in jiffies）
- `cguest_time`: 宿主操作系统虚拟处理器消耗的时间（Guest time of the task's children in jiffies）

这些变量代表了从 `/proc/${process_id}/stat` 文件中提取出来的进程状态和统计信息。你可以根据需要使用这些变量来进一步处理和分析进程信息。

