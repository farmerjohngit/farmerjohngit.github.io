title: 关于同步的一点思考-上
date: 2018-09-06 20:59:28
tags: 线程同步
---



线程同步可以说在日常开发中是用的很多，
但对于其内部如何实现的，一般人可能知道的并不多。
本篇文章将从如何实现简单的锁开始，介绍linux中的锁实现futex的优点及原理，最后分析java中同步机制如wait/notify, synchronized, ReentrantLock。

<!-- more -->
## 自己实现锁
首先，如果要你实现操作系统的锁，该如何实现？先想想这个问题，暂时不考虑性能、可用性等问题，就用最简单、粗暴的方式。当你心中有个大致的思路后，再接着往下看。

下文中的代码都是伪代码。

### 自旋
最容易想到可能是自旋：

```

volatile int status=0;

void lock(){
	
	while(!compareAndSet(0,1)){
	}
	//get lock

}

void unlock(){
	status=0;
}

boolean compareAndSet(int except,int newValue){
	//cas操作,修改status成功则返回true
}
```

上面的代码通过自旋和cas来实现一个最简单的锁。

这样实现的锁显然有个致命的缺点：耗费cpu资源。没有竞争到锁的线程会一直占用cpu资源进行cas操作，假如一个线程获得锁后要花费10s处理业务逻辑，那另外一个线程就会白白的花费10s的cpu资源。（假设系统中就只有这两个线程的情况）。

### yield+自旋
要解决自旋锁的性能问题必须让竞争锁失败的线程不`忙等`,而是在获取不到锁的时候能把cpu资源给让出来，说到让cpu资源，你可能想到了`yield()`方法，看看下面的例子：

```

volatile int status=0;

void lock(){
	
	while(!compareAndSet(0,1)){
		yield();
	}
	//get lock

}

void unlock(){
	status=0;
}

```

当线程竞争锁失败时，会调用yield方法让出cpu。需要注意的是该方法只是当前让出cpu，有可能操作系统下次还是选择运行该线程。其实现是
将当期线程移动到所在优先调度队列的末端（操作系统线程调度了解一下？有时间的话，下次写写这块内容）。也就是说，如果该线程处于优先级最高的调度队列且该队列只有该线程，那操作系统下次还是运行该线程。

自旋+yield的方式并没有完全解决问题，当系统只有两个线程竞争锁时，yield是有效的。但是如果有100个线程竞争锁，当线程1获得锁后，还有99个线程在反复的自旋+yield，线程2调用yield后，操作系统下次运行的可能是线程3；而线程3CAS失败后调用yield后，操作系统下次运行的可能是线程4...  
假如运行在单核cpu下，在竞争锁时最差只有1%的cpu利用率，导致获得锁的线程1一直被中断，执行实际业务代码时间变得更长，从而导致锁释放的时间变的更长。


### sleep+自旋
你可能从一开始就想到了，当竞争锁失败后，可以将用`Thread.sleep`将线程休眠，从而不占用cpu资源：

```

volatile int status=0;

void lock(){
	
	while(!compareAndSet(0,1)){
		sleep(10);
	}
	//get lock

}

void unlock(){
	status=0;
}

```
上述方式我们可能见的比较多，通常用于实现上层锁。该方式不适合用于操作系统级别的锁，因为作为一个底层锁，其sleep时间很难设置。sleep的时间取决于同步代码块的执行时间，sleep时间如果太短了，会导致线程切换频繁（极端情况和yield方式一样）；sleep时间如果设置的过长，会导致线程不能及时获得锁。因此没法设置一个通用的sleep值。就算sleep的值由调用者指定也不能完全解决问题：有的时候调用锁的人也不知道同步块代码会执行多久。

### park+自旋
那可不可以在获取不到锁的时候让线程释放cpu资源进行等待，当持有锁的线程释放锁的时候将等待的线程唤起呢？

```

volatile int status=0;

Queue parkQueue;

void lock(){
	
	while(!compareAndSet(0,1)){
		//
		lock_wait();
	}
	//get lock

}

void synchronized  unlock(){
	lock_notify();
}

void lock_wait(){
	//将当期线程加入到等待队列
	parkQueue.add(nowThread);
	//将当期线程释放cpu
	releaseCpu();
}
void lock_notify(){
	//得到要唤醒的线程
	Thread t=parkList.poll();
	//唤醒等待线程
	wakeAThread(t);
}

```
上面是伪代码，描述这种设计思想，至于释放cpu资源、唤醒等待线程的的具体实现，后文会再说。这种方案相比于sleep而言，只有在锁被释放的时候，竞争锁的线程才会被唤醒，不会存在过早或过完唤醒的问题。

### 小结
对于锁冲突不严重的情况，用自旋锁会更适合，试想每个线程获得锁后很短的一段时间内就释放锁，竞争锁的线程只要经历几次自旋运算后就能获得锁，那就没必要等待该线程了，因为等待线程意味着需要进入到内核态进行上下文切换，而上下文切换是有成本的并且还不低，如果锁很快就释放了，那上下文切换的开销将超过自旋。

目前操作系统中，一般是用自旋+等待结合的形式实现锁：在进入锁时先自旋一定次数，如果还没获得锁再进行等待。


## futex 
linux底层用futex实现锁，futex由一个内核层的队列和一个用户空间层的atomic integer构成。当获得锁时，尝试cas更改integer，如果integer原始值是0，则修改成功，该线程获得锁，否则就将当期线程放入到 wait queue中（即操作系统的等待队列）。

上述说法有些抽象，如果你没看明白也没关系。我们先看一下没有futex之前，linux是怎么实现锁的。

###  futex诞生之前

在futex诞生之前，linux下的同步机制可以归为两类：用户态的同步机制 和内核同步机制。 用户态的同步机制基本上就是利用原子指令实现的自旋锁。关于自旋锁其缺点也说过了，不适用于大的临界区（即锁占用时间比较长的情况）。
 
内核提供的同步机制，如semaphore等，使用的是上文说的自旋+等待的形式。 它对于大小临界区和都适用。但是因为它是内核层的（释放cpu资源是内核级调用），所以每次lock与unlock都是一次系统调用，即使没有锁冲突，也必须要通过系统调用进入内核之后才能识别。

理想的同步机制应该是没有锁冲突时在用户态利用原子指令就解决问题，而需要挂起等待时再使用内核提供的系统调用进行睡眠与唤醒。换句话说，在用户态的自旋失败时，能不能让进程挂起，由持有锁的线程释放锁时将其唤醒？
如果你没有较深入地考虑过这个问题，很可能想当然的认为类似于这样就行了（伪代码）：

```
void lock(int lockval) {
	//trylock是用户级的自旋锁
	while(!trylock(lockval)) {
		wait();//释放cpu，并将当期线程加入等待队列，是系统调用
	}
}

boolean trylock(int lockval){
	int i=0; 
	//localval=1代表上锁成功
	while(!compareAndSet(lockval,0,1)){
		if(++i>10){
			return false;
		}
	}
	return true;
}

void unlock(int lockval) {
	 compareAndSet(lockval,1,0);
	 notify();
}
```

上述代码的问题是trylock和wait两个调用之间存在一个窗口：
如果一个线程trylock失败，在调用wait时持有锁的线程释放了锁，当前线程还是会调用wait进行等待，但之后就没有人再将该线程唤醒了。
 
 
### futex诞生之后

我们来看看futex的方法定义：

```	 
	 //uaddr指向一个地址，val代表这个地址期待的值，当*uaddr==val时，才会进行wait
	 int futex_wait(int *uaddr, int val);
	 //唤醒n个在uaddr指向的锁变量上挂起等待的进程
	 int futex_wake(int *uaddr, int n);
	 
```

futex_wait真正将进程挂起之前会检查addr指向的地址的值是否等于val，如果不相等则会立即返回，由用户态继续trylock。否则将当期线程插入到一个队列中去，并挂起。

futex内部维护了一个队列，在线程挂起前会线程插入到其中，同时对于队列中的每个节点都有一个标识，代表该线程关联锁的uaddr。这样，当用户态调用futex_wake时，只需要遍历这个等待队列，把带有相同uaddr的节点所对应的进程唤醒就行了。

作为优化，futex维护的其实是个类似java 中的concurrent hashmap的结构。其持有一个总链表，总链表中每个元素都是一个带有自旋锁的子链表。调用futex_wait挂起的进程，通过其uaddr hash到某一个具体的子链表上去。这样一方面能分散对等待队列的竞争、另一方面减小单个队列的长度，便于futex_wake时的查找。每个链表各自持有一把spinlock，将"\*uaddr和val的比较操作"与"把进程加入队列的操作"保护在一个临界区中。
另外，futex是支持多进程的，当使用futex在多进程间进行同步时，需要考虑同一个物理内存地址在不同进程中的虚拟地址是不同的。


## End
本文讲述了实现锁的几种形式以及linux中futex的实现，下篇文章会讲讲Java中ReentrantLock，包括其java层的实现以及使用到的LockSupport.park的底层实现。


