title: Service使用时的一个坑：Service not registered
date: 2016-07-18 17:43:52
tags: Android
---
今天因为业务需求，要在application中启动一个service，代码如下： 
<!-- more -->
       
 
  
       
```
package com.example.myapplication;

import android.app.ActivityManager;
import android.app.Application;
import android.content.ComponentName;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.IBinder;
import android.util.Log;

import java.util.List;

import static android.R.attr.name;

/**
 * Created by wangzhi on 16/7/15.
 */

public class App extends Application {
    public static App sApp;
    ContextWrapper mContextWrapper;

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        mContextWrapper = new ContextWrapper(this);
        Intent intent = new Intent(this, MyService.class);
        bindService(intent, conn, BIND_AUTO_CREATE);
    }

    public ServiceConnection conn = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            Log.i("wangzhi", " ServiceConnection ");
            App.this.unbindService(App.this.conn);
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            Log.i("wangzhi", " onServiceDisconnected ");
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
    }


}
```

我的代码在attachBaseContext中bindService,然后再bind成功后再unbindService。
这时运行报错：

```java
FATAL EXCEPTION: main
java.lang.IllegalArgumentException: Service not registered: com.mogujie.instantrun.myapplication.App$1@418b7940
at android.app.LoadedApk.forgetServiceDispatcher(LoadedApk.java:924)
at android.app.ContextImpl.unbindService(ContextImpl.java:1264)
at com.mogujie.instantrun.myapplication.App$1.onServiceConnected(App.java:60)
at android.app.LoadedApk$ServiceDispatcher.doConnected(LoadedApk.java:1104)
at android.app.LoadedApk$ServiceDispatcher$RunConnection.run(LoadedApk.java:1121)
at android.os.Handler.handleCallback(Handler.java:615)
at android.os.Handler.dispatchMessage(Handler.java:92)
at android.os.Looper.loop(Looper.java:137)
at android.app.ActivityThread.main(ActivityThread.java:4866)
at java.lang.reflect.Method.invokeNative(Native Method)
at java.lang.reflect.Method.invoke(Method.java:511)
at com.android.internal.os.ZygoteInit$MethodAndArgsCaller.run(ZygoteInit.java:786)
at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:553)
at dalvik.system.NativeStart.main(Native Method)
```

这个错误让我很不解，我的service在manifest中的注册是没问题的，我也是先绑定service再解除绑定。在stackoverflow上看到有人说bindService和unBindService的context必须一样。在我的代码中调用bindService和unBindService的都是application。所以看起来也不像是这个原因。当到网上找不到现有的解决方案时，那就只能RTFSC – Read The Fucking Source Code.

首先我们直接看抛异常的地方的源码。

```java
// frameworks/base/core/java/android/app/LoadedApk.java

  public final IServiceConnection forgetServiceDispatcher(Context context,
            ServiceConnection c) {
        synchronized (mServices) {
          //mServices是一个map对象，我们后面再说它存的是什么
            ArrayMap<ServiceConnection, LoadedApk.ServiceDispatcher> map
                    = mServices.get(context);
            LoadedApk.ServiceDispatcher sd = null;
            if (map != null) {
                sd = map.get(c);
                if (sd != null) {
                    map.remove(c);
                    sd.doForget();
                    if (map.size() == 0) {
                        mServices.remove(context);
                    }
                    if ((sd.getFlags()&Context.BIND_DEBUG_UNBIND) != 0) {
                        ArrayMap<ServiceConnection, LoadedApk.ServiceDispatcher> holder
                                = mUnboundServices.get(context);
                        if (holder == null) {
                            holder = new ArrayMap<ServiceConnection, LoadedApk.ServiceDispatcher>();
                            mUnboundServices.put(context, holder);
                        }
                        RuntimeException ex = new IllegalArgumentException(
                                "Originally unbound here:");
                        ex.fillInStackTrace();
                        sd.setUnbindLocation(ex);
                        holder.put(c, sd);
                    }
                    //代码1
                    return sd.getIServiceConnection();
                }
            }
            ArrayMap<ServiceConnection, LoadedApk.ServiceDispatcher> holder
                    = mUnboundServices.get(context);
            if (holder != null) {
                sd = holder.get(c);
                if (sd != null) {
                    RuntimeException ex = sd.getUnbindLocation();
                    throw new IllegalArgumentException(
                            "Unbinding Service " + c
                            + " that was already unbound", ex);
                }
            }
            if (context == null) {
                throw new IllegalStateException("Unbinding Service " + c
                        + " from Context that is no longer in use: " + context);
            } else {
              //代码2
                throw new IllegalArgumentException("Service not registered: " + c);
            }
        }
    }
```

我们的异常是在代码2处抛的，说明我们没有在代码1处返回，也就是说map为null或者sd为null。我猜想在bindService的时候会把对应的context等相关信息放入mServices，可能是bindService的时候出现了问题。application的bindService是继承于ContextWrapper类，那我们来看看代码：

```java
//frameworks/base/core/java/android/content/ContextWrapper.java

 
  public boolean bindService(Intent service, ServiceConnection conn,
            int flags) {
            //ContextWrapper这个类相当于是一个装饰类，它是通过调用mBase的相关方法实现功能，  mBase是一个Context对象，其真正类型为ContextImpl;
        return mBase.bindService(service, conn, flags);
    }
    
```

```java

 //frameworks/base/core/java/android/app/ContextImpl.java

 @Override
    public boolean bindService(Intent service, ServiceConnection conn,
            int flags) {
        warnIfCallingFromSystemProcess();
        //主要实现在这个方法
        return bindServiceCommon(service, conn, flags, Process.myUserHandle());
    }

 
    private boolean bindServiceCommon(Intent service, ServiceConnection conn, int flags,
            UserHandle user) {
        IServiceConnection sd;
        if (conn == null) {
            throw new IllegalArgumentException("connection is null");
        }
        //我们绑定service时mPackageInfo肯定不为null，否则会crash
        if (mPackageInfo != null) {
        //调用了LoadedApk的getServiceDispatcher方法，注意这里传入的context是ContextImpl getOuterContext的返回值
            sd = mPackageInfo.getServiceDispatcher(conn, getOuterContext(),
                    mMainThread.getHandler(), flags);
        } else {
            throw new RuntimeException("Not supported in system context");
        }
       ...
    }

```
操作mServices的代码在getServiceDispatcher里：

```java
 //frameworks/base/core/java/android/app/LoadedApk.java
 public final IServiceConnection getServiceDispatcher(ServiceConnection c,
            Context context, Handler handler, int flags) {
        synchronized (mServices) {
            LoadedApk.ServiceDispatcher sd = null;
            ArrayMap<ServiceConnection, LoadedApk.ServiceDispatcher> map = mServices.get(context);
            if (map != null) {
                sd = map.get(c);
            }
            if (sd == null) {
                sd = new ServiceDispatcher(c, context, handler, flags);
                if (map == null) {
                    map = new ArrayMap<ServiceConnection, LoadedApk.ServiceDispatcher>();
                    mServices.put(context, map);
                }
                map.put(c, sd);
            } else {
                sd.validate(context, handler);
            }
            return sd.getIServiceConnection();
        }
    }
```
getServiceDispatcher的逻辑很简单，就是一个放入map的操作（注意是一个map嵌套了一个map）。这里的代码的逻辑是没有问题的，也就是说我们在getServiceDispatcher的时候传入的参数可能有问题。

我们来看看传入的参数，第一个就引起怀疑的就是getOuterContext有没有！

立马看下这个方法！

```java
 final Context getOuterContext() {
        return mOuterContext;
    }
```
那mOuterContext这个变量是怎么来的呢？
这个问题就复杂了，要从application创建流程说起了。

当我们启动一个app时，如果app进程不存在，则会在ActivityManagerService（如果是启动act的话）端开启一个新进程，并通过binder层层调用到ActivityThread的handleBindApplication方法

```java

//frameworks/base/core/java/android/app/ActivityThread.java

 private void handleBindApplication(AppBindData data) {
 	...
 	 
 	  if (data.instrumentationName != null) {
           ...
           LoadedApk pi = getPackageInfo(instrApp, data.compatInfo,
                    appContext.getClassLoader(), false, true, false);
            //在这里创建了一个ContextImpl ContextImpl继承了Context 
            ContextImpl instrContext = ContextImpl.createAppContext(this, pi);

            try {
                java.lang.ClassLoader cl = instrContext.getClassLoader();
                mInstrumentation = (Instrumentation)
                    cl.loadClass(data.instrumentationName.getClassName()).newInstance();
            } catch (Exception e) {
                throw new RuntimeException(
                    "Unable to instantiate instrumentation "
                    + data.instrumentationName + ": " + e.toString(), e);
            }

            mInstrumentation.init(this, instrContext, appContext,
                   new ComponentName(ii.packageName, ii.name), data.instrumentationWatcher,
                   data.instrumentationUiAutomationConnection);

         ...

        } else {
            mInstrumentation = new Instrumentation();
        }
 	 
 	 try {
             
            //LoadedApk这个类官方的解释是apk文件在内存中的表示，通过调用LoadedApk的makeApplication方法创建了一个Application对象，这个方法是我们要分析的重点
            Application app = data.info.makeApplication(data.restrictedBackupMode, null);
            mInitialApplication = app;

            // don't bring up providers in restricted mode; they may depend on the
            // app's custom Application class
            //初始化内容提供者，注意，内容提供者的初始化是在application的OnCreate之前的 。
            if (!data.restrictedBackupMode) {
                List<ProviderInfo> providers = data.providers;
                if (providers != null) {
                    installContentProviders(app, providers);
                    // For process that contains content providers, we want to
                    // ensure that the JIT is enabled "at some point".
                    mH.sendEmptyMessageDelayed(H.ENABLE_JIT, 10*1000);
                }
            }

            // Do this after providers, since instrumentation tests generally start their
            // test thread at this point, and we don't want that racing.
            try {
                mInstrumentation.onCreate(data.instrumentationArgs);
            }
            catch (Exception e) {
                throw new RuntimeException(
                    "Exception thrown in onCreate() of "
                    + data.instrumentationName + ": " + e.toString(), e);
            }

            try {
            //调用application的onCreate方法
                mInstrumentation.callApplicationOnCreate(app);
            } catch (Exception e) {
                if (!mInstrumentation.onException(app, e)) {
                    throw new RuntimeException(
                        "Unable to create application " + app.getClass().getName()
                        + ": " + e.toString(), e);
                }
            }
        } finally {
            StrictMode.setThreadPolicy(savedPolicy);
        }
 	...
 
 }
```

在上面的代码中，重点是LoadedApk的makeApplication方法，下面我们重点看下这个方法：

```java

public Application makeApplication(boolean forceDefaultAppClass,
            Instrumentation instrumentation) {
        if (mApplication != null) {
            return mApplication;
        }

        Application app = null;

        String appClass = mApplicationInfo.className;
        if (forceDefaultAppClass || (appClass == null)) {
            appClass = "android.app.Application";
        }

        try {
            java.lang.ClassLoader cl = getClassLoader();
            if (!mPackageName.equals("android")) {
                initializeJavaContextClassLoader();
            }
            //这里也是创建了一个ContextImpl对象，在createAppContext中会把 appContext 的mOuterContext指向自己（也就是appContext对象）
            ContextImpl appContext = ContextImpl.createAppContext(mActivityThread, this);
            //newApplication方法通过反射创建了application对象，并调用了application对象的attach方法，这里把appContext传了进去
            app = mActivityThread.mInstrumentation.newApplication(
                    cl, appClass, appContext);
            //代码2 在这里把appContext指向了application
            appContext.setOuterContext(app);
        } catch (Exception e) {
            if (!mActivityThread.mInstrumentation.onException(app, e)) {
                throw new RuntimeException(
                    "Unable to instantiate application " + appClass
                    + ": " + e.toString(), e);
            }
        }
        mActivityThread.mAllApplications.add(app);
        mApplication = app;

       

        return app;
    }

```

```java
//frameworks/base/core/java/android/app/Instrumentation.java

static public Application newApplication(Class<?> clazz, Context context)
            throws InstantiationException, IllegalAccessException, 
            ClassNotFoundException {
        Application app = (Application)clazz.newInstance();
        app.attach(context);
        return app;
    }
```

```java
//frameworks/base/core/java/android/app/Application.java
final void attach(Context context) {
		//这里的context就是我们上面创建的appContext
        attachBaseContext(context);
        mLoadedApk = ContextImpl.getImpl(context).mPackageInfo;
}

 protected void attachBaseContext(Context base) {
        if (mBase != null) {
            throw new IllegalStateException("Base context already set");
        }
        mBase = base;
    }
```
看到这里，我们知道在执行application的attachBaseContext方法时，application的mBase的getOuterContext返回的是appContext，而当attachBaseContext执行结束后，在代码2处，会把appContext的OutContext设置为当前application。也就是说我们在bindService时，最终存到mServices的是appContext，而attachBaseContext之后，我们调用unBindService时，通过getOuterContext拿到的是application，这就导致了在forgetServiceDispatcher 方法中 mServices.get(context)返回null，导致抛出异常。


也就是说，我们最好不要在Application的attachBaseContext方法中使用bindService方法，因为这会导致你无法成功的调用unBindService。
