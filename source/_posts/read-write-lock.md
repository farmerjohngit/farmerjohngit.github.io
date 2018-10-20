title: Java中的读写一致性
date: 2018-10-19 20:05:22
tags: 同步
---

**先说明下，本文要讨论的多线程读写是指一个线程写，一个或多个线程读，不包括多线程同时写的情况。**

更多文章见个人博客：https://github.com/farmerjohngit/myblog

试想下这样一个场景：一个线程往hashmap中写数据，一个线程往hashmap中读数据。 这样会有问题吗？如果有，那是什么问题？


相信大家都知道是有问题的，但至于到底是什么问题，可能就不是那么显而易见了。
<!-- more -->
问题有两点。
一是内存可见性的问题，hashmap存储数据的table并没有用voliate修饰，也就是说读线程可能一直读不到数据的最新值。
二是指令重排序的问题，get的时候可能得到的是一个中间状态的数据，我们看下put方法的部分代码。 

```
    final V putVal(int hash, K key, V value, boolean onlyIfAbsent,
                   boolean evict) {
       ...
        if ((p = tab[i = (n - 1) & hash]) == null)
            tab[i] = new Node<>(hash, key, value, next);
		...
	}
	
```
 
可以看到，在put操作时，如果table数组的指定位置为null，会创建一个Node对象，并放到table数组上。但我们知道jvm中` tab[i] = new Node<>(hash, key, value, next);`这样的操作不是原子的，并且可能因为指令重排序，导致另一个线程调用get取tab[i]的时候，拿到的是一个还没有调用完构造方法的对象，导致不可预料的问题发生。

上述的两个问题可以说都是因为HashMap中的内部属性没有被voliate修饰导致的，如果HashMap中的对象全部由voliate修饰，则一个线程写，一个线程读的情况是不会有问题（这里是我的猜测，证实这个猜测正确性的一点依据是ConcurrentHashMap的get并没有加锁，也就是说在Map结构里读写其实是不冲突）
 
### 创建对象的原子性问题
有的同学对于` Object obj = new Object();`这样的操作在多线程的情况下会拿到一个未初始化的对象这点可能有疑惑，这里也做个简单的说明。以上java语句分为4个步骤：

1. 在栈中分配一片空间给obj引用
2. 在jvm堆中创建一个Object对象，注意这里仅仅是分配空间，没有调用构造方法
3. 初始化第2步创建的对象，也就是调用其构造方法
4. 栈中的obj指向堆中的对象

以上步骤看起来也是没有问题的，毕竟创建的对象要调用完构造方法后才会被引用。

但问题是jvm是会对指令进行[重排序](https://www.cnblogs.com/chenyangyao/p/5269622.html)的，重排之后可能是第4步先于第3步执行，那这时候另外一个线程读到的就是没有还执行构造方法的对象，导致未知问题。jvm重排只保证重排前和重排后在**单线程**中的结果一致性。


注意java中引用的赋值操作一定是原子的，比如说a和b均是对象的情况下不管是32位还是64位jvm，`a=b`操作均是原子的。但如果a和b是long或者double原子型数据，那在32位jvm上`a=b`不一定是原子的（看jvm具体实现），有可能是分成了两个32位操作。 但是对于voliate的long,double 变量来说，其赋值是原子的。具体可以看这里https://docs.oracle.com/javase/specs/jls/se7/html/jls-17.html#jls-17.7 


### 数据库中读写一致性
跳出hashmap，在数据库中都是要用[mvcc机制](https://en.wikipedia.org/wiki/Multiversion_concurrency_control)避免加读写锁。也就是说如果不用mvcc，数据库是要加读写锁的，那为什么数据库要加读写锁呢？原因是写操作不是原子的，如果不加读写锁或mvcc，可能会读到中间状态的数据，以HBase为例，Hbase写流程分为以下几个步骤：
1.获得行锁
2.开启mvcc
3.写到内存buffer
4.写到append log
5.释放行锁
6.flush log
7.mvcc结束（这时才对读可见）

试想，如果没有不走 2，7 也不加读写锁，那在步骤3的时候，其他的线程就能读到该数据。如果说3之后出现了问题，那该条数据其实是写失败的。也就是说其他线程曾经读到过不存在的数据。

同理，在mysql中，如果不用mvcc也不用读写锁，一个事务还没commit，其中的数据就能被读到，如果用读写锁，一个事务会对中更改的数据加写锁，这时其他读操作会阻塞，直到事务提交，对于性能有很大的影响，所以大多数情况下数据库都采用MVCC机制实现非锁定读。