title: 分布式Redis深度历险-Clustor
date: 2018-09-05 21:11:28
tags: redis
---

本文为分布式Redis深度历险系列的第三篇，主要内容为Redis的Clustor，也就是Redis集群功能。

Redis集群是Redis官方提供的分布式方案，整个集群通过将所有数据分成16384个槽来进行数据共享。
<!-- more -->

### 集群基础实现

一个集群由多个Redis节点组成，不同的节点通过`CLUSTOR MEET`命令进行连接：

`CLUSTOR MEET <ip> <port>`

收到命令的节点会与命令中指定的目标节点进行握手，握手成功后目标节点会加入到集群中,看个例子,图片来自于[Redis的设计与实现](http://redisbook.com/preview/cluster/node.html)：

![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-1.png
)


![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-2.png
)


![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-3.png
)


![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-4.png
)


![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-5.png
)

### 槽分配
一个集群的所有数据被分为16384个槽，可以通过`CLUSTER ADDSLOTS`命令将槽指派给对应的节点。当所有的槽都有节点负责时，集群处于上线状态，否则处于下线状态不对外提供服务。

clusterNode的位数组slots代表一个节点负责的槽信息。

```

struct clusterNode {


    unsigned char slots[16384/8]; /* slots handled by this node */

    int numslots;   /* Number of slots handled by this node */

    ...
}

```

看个例子，下图中1、3、5、8、9、10位的值为1，代表该节点负责槽1、3、5、8、9、10。

每个Redis Server上都有一个ClusterState的对象，代表了该Server所在集群的信息，其中字段slots记录了集群中所有节点负责的槽信息。

```
typedef struct clusterState {

    // 负责处理各个槽的节点
    // 例如 slots[i] = clusterNode_A 表示槽 i 由节点 A 处理
    // slots[i] = null 代表该槽目前没有节点负责
    clusterNode *slots[REDIS_CLUSTER_SLOTS];

}
```

### 槽重分配
可以通过redis-trib工具对槽重新分配，重分配的实现步骤如下：

1. 通知目标节点准备好接收槽
2. 通知源节点准备好发送槽
3. 向源节点发送命令：`CLUSTER GETKEYSINSLOT <slot> <count>`从源节点获取最多count个槽slot的key
4. 对于步骤3的每个key，都向源节点发送一个`MIGRATE <target_ip> <target_port> <key_name> 0 <timeout> `命令，将被选中的键原子的从源节点迁移至目标节点。
5. 重复步骤3、4。直到槽slot的所有键值对都被迁移到目标节点
6. 将槽slot指派给目标节点的信息发送到整个集群。



在槽重分配的过程中，槽中的一部分数据保存着源节点，另一部分保存在目标节点。这时如果要客户端向源节点发送一个命令，且相关数据在一个正在迁移槽中，源节点处理步骤如图:
![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-112.png
)

当客户端收到一个ASK错误的时候，会根据返回的信息向目标节点重新发起一次请求。

ASK和MOVED的区别主要是ASK是一次性的，MOVED是永久性的，有点像Http协议中的301和302。
 

### 一次命令执行过程
我们来看clustor下一次命令的请求过程,假设执行命令 `get testKey`

1. clustor client在运行前需要配置若干个server节点的ip和port。我们称这些节点为种子节点。

2. clustor的客户端在执行命令时，会先通过计算得到key的槽信息，计算规则为：`getCRC16(key) & (16384 - 1)`，得到槽信息后，会从一个缓存map中获得槽对应的redis server信息，如果能获取到，则调到第4步
3. 向种子节点发送`slots`命令以获得整个集群的槽分布信息，然后跳转到第2步重试命令
4. 向负责该槽的server发起调用
server处理如图：
![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-111.png
)
 
 
 
6. 客户端如果收到MOVED错误，则根据对应的地址跳转到第4步重新请求，
7. 客户段如果收到ASK错误，则根据对应的地址跳转到第4步重新请求，并在请求前带上ASKING标识。

以上步骤大致就是redis clustor下一次命令请求的过程，但忽略了一个细节，如果要查找的数据锁所在的槽正在重分配怎么办？
 

### Redis故障转移
#### 疑似下线与已下线
集群中每个Redis节点都会定期的向集群中的其他节点发送PING消息，如果目标节点没有在有效时间内回复PONG消息，则会被标记为疑似下线。同时将该信息发送给其他节点。当一个集群中有半数负责处理槽的主节点都将某个节点A标记为疑似下线后，那么A会被标记为已下线，将A标记为已下线的节点会将该信息发送给其他节点。

比如说有A,B,C,D,E 5个主节点。E有F、G两个从节点。
当E节点发生异常后，其他节点发送给A的PING消息将不能得到正常回复。当过了最大超时时间后，假设A,B先将E标记为疑似下线；之后C也会将E标记为疑似下线，这时C发现集群中由3个节点（A、B、C）都将E标记为疑似下线，超过集群复制槽的主节点个数的一半(>2.5)则会将E标记为已下线，并向集群广播E下线的消息。


#### 选取新的主节点
当F、G（E的从节点）收到E被标记已下线的消息后，会根据Raft算法选举出一个新的主节点，新的主节点会将E复制的所有槽指派给自己，然后向集群广播消息，通知其他节点新的主节点信息。

选举新的主节点算法与选举Sentinel头节点的[过程](http://www.farmerjohn.top/2018/08/20/redis-sentinel/#%E9%80%89%E4%B8%BE%E9%A2%86%E5%A4%B4Sentinel)很像：

  1. 集群的配置纪元是一个自增计数器，它的初始值为0.

  2. 当集群里的某个节点开始一次故障转移操作时，集群配置纪元的值会被增一。

  3. 对于每个配置纪元，集群里每个负责处理槽的主节点都有一次投票的机会，而第一个向主节点要求投票的从节点将获得主节点的投票。

  4. 档从节点发现自己正在复制的主节点进入已下线状态时，从节点会想集群广播一条CLUSTER_TYPE_FAILOVER_AUTH_REQUEST消息，要求所有接收到这条消息、并且具有投票权的主节点向这个从节点投票。

  5. 如果一个主节点具有投票权（它正在负责处理槽），并且这个主节点尚未投票给其他从节点，那么主节点将向要求投票的从节点返回一条CLUSTERMSG_TYPE_FAILOVER_AUTH_ACK消息，表示这个主节点支持从节点成为新的主节点。

  6. 每个参与选举的从节点都会接收CLUSTERMSG_TYPE_FAILOVER_AUTH_ACK消息，并根据自己收到了多少条这种消息来同济自己获得了多少主节点的支持。

  7. 如果集群里有N个具有投票权的主节点，那么当一个从节点收集到大于等于N/2+1张支持票时，这个从节点就会当选为新的主节点。

  8. 因为在每一个配置纪元里面，每个具有投票权的主节点只能投一次票，所以如果有N个主节点进行投票，那么具有大于等于N/2+1张支持票的从节点只会有一个，这确保了新的主节点只会有一个。

  9. 如果在一个配置纪元里面没有从节点能收集到足够多的支持票，那么集群进入一个新的配置纪元，并再次进行选举，知道选出新的主节点为止。



### Redis常用分布式实现方案
最后，聊聊redis集群的其他两种实现方案。

#### client做分片
客户端做路由，采用一致性hash算法，将key映射到对应的redis节点上。
其优点是实现简单，没有引用其他中间件。
缺点也很明显：是一种静态分片方案，扩容性差。

Jedis中的ShardedJedis是该方案的实现。

#### proxy做分片

该方案在client与redis之间引入一个代理层。client的所有操作都发送给代理层，由代理层实现路由转发给不同的redis服务器。

![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-clustor-113.webp
)

其优点是: 路由规则可自定义，扩容方便。
缺点是： 代理层有单点问题，多一层转发的网络开销

其开源实现有twitter的[twemproxy](https://github.com/twitter/twemproxy)
和豌豆荚的[codis](https://github.com/CodisLabs/codis)

 
### 结束
分布式redis深度历险系列到此为止了，之后一个系列会详细讲讲单机Redis的实现，包括Redis的底层数据结构、对内存占用的优化、基于事件的处理机制、持久化的实现等等偏底层的内容，敬请期待~
 
 