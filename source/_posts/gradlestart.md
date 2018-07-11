title: gradle入门与在android中的使用
date: 2016-03-12 23:18:52
tags:
---
一、gradle简介
====
### gradle是什么？ 
Gradle是一个基于Apache Ant和Apache Maven概念的项目自动化建构工具。它使用一种基于Groovy的特定领域语言来声明项目设置，而不是传统的XML。当前其支持的语言限于Java、Groovy和Scala，计划未来将支持更多的语言。

gradle的维基百科解释如上，对于没有接触过构建工具的同学可能很难看明白。 所以下面给个我个人对gradle的理解：
在我们coding的过程中，可能常常要用到一些其他的library，比如说下拉刷新的library,okhttp的library等等。如果不使用自动化构建工具的话，我们只能把library的jar包拷贝到我们自己的工程中使用。这对于一个稍微大些的工程来说都是很麻烦的。而且在app的开发中，我们通常需要分不同的版本，比如说供测试用的debug包，供发布用的release包，甚至会根据不同的app store来推出不同的渠道包。如果这些都依靠developer自己来维护的话，势必会带来问题。对于写一些基础库的同学来说，如何在基础库更新后能让使用者方便的使用不同的的库版本也是一个问题。而项目自动化建构工具就是用来解决这些问题的。常见的自动化构建工具有ant、maven、gradle等等。gradle是我用的最多的一种构建工具，也是我个人认为最好用的一种


### 为什么是gradle
1.  maven是基于xml的，xml虽然简单易懂，但是很难描述出if(){}else{}的条件选择逻辑。而grale则是基于groovy的，groovy是基于java拓展的脚本语言，对于java developer来说，学习groovy成本可以说很小，写起来却很方便。灵活性也很高
2. gradle一次编译是由一个一个task组成的，你能根据需要执行任意的task，配合dsl能更加细致的控制编译流程

更多细节见：[gradle vs maven](http://gradle.org/maven_vs_gradle/)  

<!-- more -->
二、groovy简介
===
前面说过，groovy是一种基于java的动态语言。它也是跑在jvm上的。groovy为什么能跑在java的虚拟机上呢？这听上去让人有些难以理解。
实际上，在groovy的编译阶段，groovy的编译器就会把groovy源码编译成class文件，class文件？没错！就是class文件。我们知道，java在编译后也是编译成class文件，然后交给虚拟机去执行的。换句话说，jvm的输入是class文件，只要你是标准的class文件，jvm是不会管你是由什么语言编译来的，它都会执行！
下面我就简单的说下groovy的一些在gradle中常用的语法，以便后面的gradle学习

### 动态类型
gradle与js一样，支持动态类型：

``` groovy
def temp = "groovy" //def是groovy中定义变量的关键字
temp = 1 //groovy可以不用分号结尾～
println temp
```

输出结果为1 

### 函数的返回
函数的返回类型也可以定义为def的:

``` groovy
def getValue(){
    retrun "hello world"
}
```
函数可以省略return语句（即使该函数是有返回值的），在无return语句的情况下，最后一行代码的执行结果即返回值

``` groovy
def getValue(){
//定义了一个List变量strList, strList中有三个变量："hello","groovy"和100 
    def strList=["hello","groovy",100] 
}
	
def getValue(){
    def str="hello world" //返回值为"hello world"
}
```

### 闭包
闭包的相关概念我就不说了，我们来看闭包在groovy中的使用：

遍历一个Collection

``` groovy
def list = ["gradle", "groovy", "closure"]
//{}内的代码块就是一个闭包
list.each{
    println it//闭包中的it是一个关键字，指向被调用的外部集合的每个值。
}
```
	
输出结果：

	gradle 
	groovy 
	closure
	
 
我们可以通过传递参数给闭包覆盖it关键字

``` groovy
def list = ["gradle", "groovy", "closure"]
//{}内的代码块就是一个闭包
list.each{ eachItem-> //箭头的前面是参数定义，后面是代码 
    println eachItem//用eachItem覆盖了it
}
```
	
输出结果同上


遍历一个map：

``` groovy
//[key:value,key:value]代表定义一个map
def hash = [name:"Andy", "VPN-#":45]
hash.each{ key, value ->//传递给闭包两个参数
    println "${key} : ${value}"
}
```
	

看完了上面的示例，你可能会有疑问，hash.each{} 到底是什么意思呢？是调用hash变量的each方法吗？这里我告诉大家，是调用each方法

那如果是调用方法，为什么没有我们在java方法调用中的圆括号呢？

基于这个疑问，我们去看下.each这个方法的定义
 
 ``` groovy
public static <T> Iterable<T> each(Iterable<T> self, @ClosureParams(FirstParam.FirstGenericType.class) Closure closure) {
    each(self.iterator(), closure);
    return self;
}
```

当我们在调用.each方法时，第一个参数self传进去代表调用each方法的变量，第二个参数代表each{}包裹起来的代码块。而在groovy中，当函数最后的一个参数是闭包的话，可以省略圆括号。（有同学可能会问each方法的定义明明有两个参数，但在调用时只传入了一个closure参数，没有传入self参数啊。对于这个问题，在这里我们不深究了，可以简单的认为在编译时，groovy编译器会帮我们处理。）


``` groovy
def testClosure(String name, Closure closure){
    println ("${name} say: ")//"${name} say: "等价于name+" say:"类似于jsp中EL表达式
    closure.call()
}
	
//下面的两种调用都是正确的
testClosure  "testWithoutParenthesis", {
    println "i am testWithoutParenthesis\n"
}

testClosure ( "testWithParenthesis", {
    println "i am testWithParenthesis\n"
} )
```

输出：

		testWithoutParenthesis say: 
		i am testWithoutParenthesis
		
		testWithParenthesis say: 
		i am testWithParenthesis


我们在gradle 中常常看到以下代码： 
``` groovy
task hello{
    doLast{
        println "Hello Task"
    }
}
```
有了上面的分析，你应该知道上面的代码就等价于：
``` groovy
task hello{
    (doLast ({
        println "Hello Task"
    }))
}
```
	


好了，看了上面的内容再加上自己google一些资料，相信现在的你已经对groovy有了一些了解。下面我们开始看gradle的内容！



### 三、Gradle

gradle官网有[User Guide](https://docs.gradle.org/current/userguide/userguide.html) ,我个人感觉太长了，而且有很多我们可能是很少用到的东西，所以在这里我就挑一些在开发中比较常用的点来说下。如果大家希望比较系统的了解gradle的话建议还是要看下gradle的官方文档。

### multi-project

我们用android studio 建立一个工程时起目录结构如下：

我们可以看到在MyApplicaton 目录有个setting.gradle 和一个build.gradle文件在MyApplication/app目录下也有个build.gradle 文件
那么这三个gradle文件分别代表什么呢？
在gradle中，每一个待编译的工程都叫一个Project。每个Project下都会有一个build.gradle的文件。也就是说一个build.gradle 文件就代表一个工程。 我们执行gradle peojects 命令可以看到：那也就说明我们用android studio新建的一个MyAppication目录下确实包括了两个gradle工程：MyApplication和app.
 
在gradle中,是支持[multi-project](https://docs.gradle.org/current/userguide/intro_multi_project_builds.html)构建的.在multi-project中的root project中要定义一个settings.gradle文件，该文件主要作用就是告诉gradle这个multi-project有哪些subproject。我们来看下MyApplicastion/settings.gradle的内容：
``` groovy
	include ':app'//代表有一个叫app的subproject
```
在MyApplication中，MyApplication中有一个settings.gradle的文件，所以它是root project也是app的father project。
 
 
 
 
### gradle 工作流程

如图，gradle的流程分为3个阶段：
	![alt text](http://7xrsw2.com1.z0.glb.clouddn.com/image028.png "title")

	

1.初始化阶段(Initialization Phases):执行setting.gradle。settings.gradle会被转化为Settings的对象.settings.gradle决定哪个project应该加入构建。对于每一个工程创建一个[Project](https://docs.gradle.org/current/dsl/org.gradle.api.Project.html)对象。

2.配置阶段(Configuration Phases):在这个阶段，所有参与构建的工程的build.gradle脚本将会被执行。task也是在这个阶段定义的,并被添加到一个有向图中。

3.执行阶段(Execution Phases):Gradle会执行指定的task（例如，在命令行中执行gradle build，将会执行build这个task）



gradle的工作流程详见官方文档:
https://docs.gradle.org/current/userguide/build_lifecycle.html


在上面提到了task的概念，那么，task是什么呢？


在gradle中,每个Project是由一个或多个task组成的，一个task代表构建过程中的原子执行单位（atomic piece）,例如讲java源文件编译成class文件，就是一个task。
我们可以在gradle工程下执行gradle tasks 这个命令，这个命令代表执行 "tasks"这个task，而这个task的含义是打印出该工程下的所有task。
如图：
	![alt text](http://7xrsw2.com1.z0.glb.clouddn.com/blogt11.png "title")
 

在gradle中，task之间是可以有依赖的。例如，在下面的代码中b依赖a，c依赖b，那么当我们执行gradle C时，会先执行a，然后执行b，最后才会执行c
``` groovy
	task A << {println 'This is task A'}
	task B << {println 'This is task B'}
	task C << {println 'This is task C'}
	B.dependsOn A
	C.dependsOn B
```
输出如下：

	This is task A
	This is task B
	This is task C
	


说到这里，你对于gradle的工作流程应该有一个大致认识，我们需要记住以下几点：

1.gradle最先会执行settings.gradle中的内容

2.解析所有在settings.gradle中配置的project.

3.执行你指定的task




下面将结合自己在项目中的gradle实战中遇到的一些问题，来理解gradle以及android gradle中的一些知识

### 增量构建
在一个android工程由源码变成.apk文件的打包过程中，涉及到很多的task，如将源码编译成class的compileSource Task，将class文件变成dex文件的dextask, 将资源文件用aapt打包成.ap_的processResource Task.等等。这些task是不是每次打包都会执行呢？如果我们只是改了一行代码，难道处理资源的processResource Task也要执行吗？显然，在只更改代码的情况下，执行资源相关的task是多余的，反之亦然。

在gradle中，每个task都有自己的输入和输出，gradle会把task的输入和输出缓存在文件中（以md5之类的形式），当执行一个task时，如果这个task的输入和输出都与前一次执行相同，那么gradle 将不会执行该task，在log中会在task后面写上[UP-TO-DATE]表明该task输入输出没有变化，这次构建没有执行。


### doLast

我们常常在gradle中看到这样的写法：
``` groovy
task hello<<{
    println "hello gradle"
}
```
<<等价于doLast,因此上面的写法就等价于
``` groovy
task hello{
    doLast{
        println "hello gradle"
    }
}	
```

一个task是以一个action的链表组成的，当一个task被执行时，它会依次的执行该task的action链表，而doLast 就表示将一个action插入到该task action链表的末尾。当task执行完时就会执行doLast里面的内容。doFirst则与之相反。



### 插入自己定义的task
我之前一直在做动态加载，当时有个需求是，将需要动态加载的组件在dex之前切分出来，做成单独的dex文件。 然后在运行时将dex文件动态加载。那么，我们首先要找到dex的task，并创建一个我们自己的task，然后让dex task依赖我们自定义的task。

``` groovy
	project.afterEvaluate {
	    android.applicationVariants.each { variant ->
	      //variant.name 就是productFlavors+ buildTypes
	        //用android studio新建一个工程，会默认有debug和release两种buildType,但是没有productFlavors。在这种情况下，dex task的名字为dexDebug和dexRelease
	        def dx = tasks.findByName("dex${variant.name.capitalize()}")
	        //or def dx = variant.dex
	        
	        def dexSplit = "dexSplit${variant.name.capitalize()}"
	      
	        task(dexSplit) << {
	            dx.inputs.files.files.each{jarFile->
	                jarFile = jarFile as File
	                //在使用multidex或者proguard的工程，会有一个task将所有的class文件打包成一个jar文件
	                if(jarFile.name.endsWith(".jar")){
	                    //将jar包解压，并将指定的class文件提取出来
	                    //将提取出来的class进行dex操作。剩余的class打成jar包。 
	
	                }
	            }
	        }
	        //让dexSplit这个task依赖dx task依赖的task
	        tasks.findByName(dexSplit).dependsOn dx.taskDependencies.getDependencies(dx)
	        //让dx 依赖dexsplit
	        dx.dependsOn tasks.findByName(dexSplit)
	    	//上面两步操作类似于链表插入节点
	    }
	} 
```

