title: 分布式Redis深度历险-Sentinel
date: 2018-08-20 12:39:38
tags: redis
---

本文为分布式Redis深度历险系列的第二篇，主要内容为Redis的Sentinel功能。

上一篇介绍了Redis的主从服务器之间是如何同步数据的。试想下，在一主一从或一主多从的结构下，如果主服务器挂了，整个集群就不可用了，单点问题并没有解决。Redis使用Sentinel解决该问题，保障集群的高可用。
<!-- more -->
### 如何保障集群高可用
保障集群高可用，要具备如下能力：

 - 能监测服务器的状态，当主服务器不可用时，能及时发现
 - 当主服务器不可用时，选择一台最合适的从服务器替代原有主服务器
 - 存储相同数据的主服务器同一时刻只有一台


要实现上述功能，最直观的做法就是，使用一台监控服务器来监视Redis
服务器的状态。![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-sentinel-1.png
)

监控服务器和主从服务器间维护一个心跳连接，当超出一定时间没有收到主服务器心跳时，主服务器就会被标记为下线，然后通知从服务器上线成为主服务器。![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-sentinel-2.png
)

当原来的主服务器上线后，监控服务器会将其转换为从服务器。
![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-sentinel-3.png
)

按照上述流程似乎解决了集群高可用的问题，但似乎有哪里不对：如果监控服务器出了问题怎么办？我们可以在加上一个从监控服务器，当主服务器不可用的时候顶上。
![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-sentinel-4.png
)

但问题是谁来监控'监控服务器'呢？子子孙孙无穷尽也。。

先把疑问放在一旁，先来看下Redis Sentinel集群的实现

### Sentinel

和上一小节的想法一样，Redis通过增加额外的Sentinel服务器来监控数据服务器，Sentinel会与所有的主服务器和从服务器保存连接，用以监听服务器状态以及向服务器下达命令。

![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-sentinel-5.png
)

Sentinel本身是一个特殊状态的Redis服务器，启动命令：
`redis-server /xxx/sentinel.conf --sentinel`,sentinel模式下的启动流程与普通redis server是不一样的，比如说不会去加载RDB文件以及AOF文件，本身也不会存储业务数据。

#### 与主服务器建立连接
Sentinel启动后，会与配置文件中提供的所有主服务器建立两个连接，一个是命令连接，一个是订阅连接。

命令连接用于向服务器发送命令。

订阅连接则是用于订阅服务器的`_sentinel_:hello`频道，用于获取其他Sentinel信息，下文会详细说。


#### 获取主服务器信息

Sentinel会以一定频率向主服务器发送`Info`命令获取信息，包括主服务器自身的信息比如说服务器id等，以及对应的从服务器信息，包括ip和port。Sentinel会根据info命令返回的信息更新自己保存的服务器信息，并会与从服务器建立连接。


#### 获取从服务器信息

与和主服务器的交互相似，Sentinel也会以一定频率通过`Info`命令获取从服务器信息，包括：从服务器ID，从服务器与主服务器的连接状态，从服务器的优先级，从服务器的复制偏移等等。


#### 向服务器订阅和发布消息

在**如何保障集群高可用**小节留下了一个疑问：用如何保证监视服务器的高可用？ 在这里我们可以先给出简单回答：用一个监视服务器集群（也就是Sentinel集群）。如何实现，如何保证监视服务器的一致性暂且先不说，我们只要记住需要用若干台Sentinel来保障高可用，那一个Sentinel是如何感知其他的Sentinel的呢？

前面说过，Sentinel在与服务器建立连接时，会建立两个连接，其中一个是订阅连接。Sentinel会定时的通过订阅连接向`_sentinel_:hello`频道频道发送消息（对Redis发布订阅功能不太了解的同学可以去去了解下），其中包括：

- Sentinel本身的信息，如ip地址、端口号、配置纪元（见下文）等
- Sentinel监视的主服务器的信息，包括ip、端口、配置纪元（见下文）等

同时，Sentinel也会订阅`_sentinel_:hello`频道的消息，也就是说Sentinel即向该频道发布消息，又从该频道订阅消息。
![image](https://wangzhi-blog.oss-cn-hangzhou.aliyuncs.com/redis-sentinel-6.png
)

Sentinel有一个字典对象`sentinels`，保存着监视同一主服务器的其他所有Sentinel服务器，当一个Sentinel接收到来自`_sentinel_:hello`频道的消息时，会先比较发送该消息的是不是自己，如果是则忽略，否则将更新`sentinels`中的内容，并对新的Sentinel建立连接。


#### 主观下线

Sentinel默认会以每秒一次的频率向所有建立连接的服务器（主服务器，从服务器，Sentinel服务器）发送`PING`命令，如果在`down-after-milliseconds`内都没有收到有效回复,Sentinel会将该服务器标记为主观下线，代表该Sentinel认为这台服务器已经下线了。需要注意的是不同Sentinel的`down-after-milliseconds`是可以不同的。

#### 客观下线

为了确保服务器真的已经下线，当Sentinel将某个服务器标记为主观下线后，它会向其他的Sentinel实例发送`Sentinel is-master-down-by-addr`命令，接收到该命令的Sentinel实例会回复主服务器的状态，代表该Sentinel对该主服务器的连接情况。

Sentinel会统计发出的所有`Sentinel is-master-down-by-addr`命令的回复，并统计同意将主服务器下线的数量，如果该数量超出了某个阈值，就会将该主服务器标记为客观下线。

#### 选举领头Sentinel

当Sentinel将一个主服务器标记为客观下线后，监视该服务器的各个Sentinel会通过`Raft`算法进行协商，选举出一个领头的Sentinel。
建议你先看`Raft`算法的基础知识，再来看下文。

规则：

- 所有的Sentinel都有可能成为领头Sentinel的资格
- 每次选举后，无论有没有选出领头Sentinel，配置纪元都会+1
- 在某个纪元里，每个Sentinel都有为投票的机会
- 我们称要求其他人选举自己的Sentinel称为源Sentinel，将被要求投票的Sentinel称为目标Sentinel
- 每个发现主服务器被标记为客观下线且还没有被其他Sentinel要求投票的Sentinel都会要求其他Sentinel将自己设置为头
- 目标Sentinel在一个配置纪元里，一旦为某个Sentinel（也可能是它自己）投票后，对于之后收到的要求投票的命令，将拒绝
- 目标Sentinel对于要求投票的命令将回复自己选举的Sentinel的id以及当前配置纪元
- 源Sentinel在接收到要求投票的回复后：如果回复的配置纪元与自己的相同，则再检测目标Sentinel选举的头Sentinel是不是自己
- 如果某个Sentinel被半数以上的Sentinel设置成了领头Sentinel，那它将称为领头Sentinel
- 一个配置纪元只会选出一个头（因为一个头需要半数以上的支持）
- 如果在给定时间内，还没有选出头，则过段时间再次选举（配置纪元会+1）



还记得我们在文章开头提出的如何保证Redis服务器高可用的问题吗？
答案就是使用若干台Sentinel服务器，通过`Raft`一致性算法来保障集群的高可用，只要Sentinel服务器有一半以上的节点都正常，那集群就是可用的。

#### 故障转移

领头Sentinel将会进行以下3个步骤进行故障转移：

1.在已下线主服务器的所有从服务器中，挑选出一个作为新的主服务器

2.将其他从服务器的主服务器设置成新的

3.将已下线的主服务器的role改成从服务器，并将其主服务器设置成新的，当该服务器重新上线后，就会一个从服务器的角色继续工作

第一步中挑选新的主服务器的规则如下：

1.过滤掉所有已下线的从服务器

2.过滤掉最近5秒没有回复过Sentinel命令的从服务器

3.过滤掉与原主服务器断开时间超过down-after-milliseconds*10的从服务器

4.根据从服务器的优先级进行排序，选择优先级最高的那个

5.如果有多个从服务器优先级相同，则选取复制偏移量最大的那个

6.如果上一步的服务器还有多个，则选取id最小的那个

 




