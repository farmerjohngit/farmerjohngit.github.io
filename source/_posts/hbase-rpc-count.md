title: HBase Rpc返回数据之谜
date: 2018-01-04 17:53:04
tags: hbase
---

接触HBase也有一段时间了，对于HBase scan的一次Rpc到底返回多少数据的问题一直不是很理解。

最近刚好遇到这方面的问题，所以就抽空看了一下，终于把这一块看明白了。

代码基于HBase 1.2.6

### 结论
先说结论：
	在batch为false的情况下。
	
	1. 一次Rpc返回的数据量受两个因素决定，scan.caching和scan.maxResultSize。
	2. 其中caching限制返回的最大行数，默认为Integer.MAX。
	3. maxResultSize限制返回的数据大小，默认为2 * 1024 * 1024字节
	4. 一次Rpc返回的结果必须同时满足maxResultSize和caching两点限制。
	5. 一次rpc返回的数据可能包括不完整的行
	
看完了结论，没兴趣或者没精力了解细节的同学可以先下车了~

### 客户端
待补充..
### 服务端
待补充..
### 感想
待补充..
