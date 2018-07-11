title:  深入分析FragmentManager管理机制(一)
date: 2016-07-17 16:43:34
tags:
---
 

Fragment是在Android中使用的很多的一个组件。虽然现在有很多人主张不用Fragment([我为什么主张反对使用Android Fragment](https://corner.squareup.com/2014/10/advocating-against-android-fragments.html) ) 。但在我们实际项目中fragment可以说是不可缺少的。 而Fragment的调度，生命周期等又是与FragmentManager这个类息息相关的。因此，本篇博客将带大家深入分析FragmentManager及相关类的源码，了解Fragment的调度过程。 

我们以FragmentManager 一个最基本的使用为入口，看看FragmentManager里面到底做了些什么,
假设我们有一个按钮  点击后往界面上添加一个fragment,添加fragme的方法如下：

   
```java
//开启FragmentManager的一个事务，加入了一个Fragment并提交
FragmentManager fm = getSupportFragmentManager();
FragmentTransaction ft = fm.beginTransaction();
ft.add(R.id.id_content, new CustomFragment(),"tag");
ft.commit();
```
<!-- more -->
上面值得分析的方法有两个，一个是add,一个是commit。我们一个一个看。

首先是add方法，我们跟进去看下。代码在android/app/FragmentTransaction.java


    public abstract FragmentTransaction add(int containerViewId, Fragment fragment, String tag);

<!-- more -->
是抽象方法，看其子类实现。代码在 androi/app/BackStackRecord.java

    public FragmentTransaction add(int containerViewId, Fragment fragment, String tag) {
        doAddOp(containerViewId, fragment, tag, OP_ADD);
        return this;
    }

    private void doAddOp(int containerViewId, Fragment fragment, String tag, int opcmd) {
        fragment.mFragmentManager = mManager;

        if (tag != null) {
            if (fragment.mTag != null && !tag.equals(fragment.mTag)) {
                throw new IllegalStateException("Can't change tag of fragment "
                        + fragment + ": was " + fragment.mTag
                        + " now " + tag);
            }
            fragment.mTag = tag;
        }

        if (containerViewId != 0) {
            if (fragment.mFragmentId != 0 && fragment.mFragmentId != containerViewId) {
                throw new IllegalStateException("Can't change container ID of fragment "
                        + fragment + ": was " + fragment.mFragmentId
                        + " now " + containerViewId);
            }
            fragment.mContainerId = fragment.mFragmentId = containerViewId;
        }

        Op op = new Op();
        op.cmd = opcmd;
        op.fragment = fragment;
        addOp(op);
    }


在BackStackRecord的add方法中调用了私有方法doAddOp ，最后一个参数传入的是常量OP_ADD，在doAddOp中，进行了一些检查。然后构造了一个Op对象，op的cmd为传入的OP_ADD，op的fragment为我们要添加的fragment。然后调用addOp方法，并将构造的op变量传入。
一个op对象就等于一个操作命令（add/remove/show/hide等）。


    void addOp(Op op) {
      //这里应该很熟悉吧，经典的队列入队操作.mHead是队首指针，mTail是队尾指针。
       if (mHead == null) {
           mHead = mTail = op;
       } else {
           op.prev = mTail;
           mTail.next = op;
           mTail = op;
       }
       //mEnterAnim 是调用setCustomAnimations方法设置的fragment切换动画
       op.enterAnim = mEnterAnim;
       op.exitAnim = mExitAnim;
       op.popEnterAnim = mPopEnterAnim;
       op.popExitAnim = mPopExitAnim;
       //mNumOp代表了队列中有多少个op对象
       mNumOp++;
    }

在addOp方法中将op对象放入队列中，并将设置的fragment切换动画赋值给op。

到这里，这一串方法链调用就结束了，简单的说就是将我们调用的ft.add 方法封装成一个指令，然后放入队列中。那真正对fragment进行操作的在哪里呢？ 想都不用想，肯定在我们要分析的第二个方法commit中。


    /**
     * Schedules a commit of this transaction.  The commit does
     * not happen immediately; it will be scheduled as work on the main thread
     * to be done the next time that thread is ready.
     *
     * <p class="note">A transaction can only be committed with this method
     * prior to its containing activity saving its state.  If the commit is
     * attempted after that point, an exception will be thrown.  This is
     * because the state after the commit can be lost if the activity needs to
     * be restored from its state.  See {@link #commitAllowingStateLoss()} for
     * situations where it may be okay to lose the commit.</p>
     *
     * @return Returns the identifier of this transaction's back stack entry,
     * if {@link #addToBackStack(String)} had been called.  Otherwise, returns
     * a negative number.
     */

    public abstract int commit();



我们注意这一句The commit does not happen immediately; it will be scheduled as work on the main threadto be done the next time that thread is ready.
这里说 commit方法调用后，这次会话并不会马上执行，而是会在下一次主线程调度的时候执行。 在这里你应该会有疑问，什么叫下一次主线程调度？  我们带着这个疑问往下看。



    public int commit() {
        return commitInternal(false);
    }

    public int commitAllowingStateLoss() {
        return commitInternal(true);
    }

    int commitInternal(boolean allowStateLoss) {
      //mCommitted 代表该次会话是否已经commit过了，commit方法只能执行一次
        if (mCommitted) {
            throw new IllegalStateException("commit already called");
        }
        if (FragmentManagerImpl.DEBUG) {
            Log.v(TAG, "Commit: " + this);
            LogWriter logw = new LogWriter(Log.VERBOSE, TAG);
            PrintWriter pw = new FastPrintWriter(logw, false, 1024);
            dump("  ", null, pw, null);
            pw.flush();
        }
        //标记该BackStackRecord已经commit过
        mCommitted = true;

        //mAddToBackStack代表是否，默认为false。调用addToBackStack会设置为true
        if (mAddToBackStack) {
            mIndex = mManager.allocBackStackIndex(this);
        } else {
            mIndex = -1;
        }

        mManager.enqueueAction(this, allowStateLoss);
        return mIndex;
    }




在commitInternal方法中，因为我们没有调用addToBackStack，所以mAddToBackStack为false。mIndex为-1.

mManager在这里是  FragmentManagerImp对象。


      /**
        * Adds an action to the queue of pending actions.
        *
        * @param action the action to add
        * @param allowStateLoss whether to allow loss of state information
        * @throws IllegalStateException if the activity has been destroyed
        */
       public void enqueueAction(Runnable action, boolean allowStateLoss) {
         //先忽略这里
           if (!allowStateLoss) {
               checkStateLoss();
           }
           synchronized (this) {
               if (mDestroyed || mHost == null) {
                   throw new IllegalStateException("Activity has been destroyed");
               }
               if (mPendingActions == null) {
                   mPendingActions = new ArrayList<Runnable>();
               }
               mPendingActions.add(action);
               if (mPendingActions.size() == 1) {
                   mHost.getHandler().removeCallbacks(mExecCommit);
                   mHost.getHandler().post(mExecCommit);
               }
           }
       }

enqueueAction第一个参数是刚刚的BackStackRecord对象（BackStackRecord实现了Runnable），第二个参数在这里为false。
在这个方法里，将action放入链表 mPendingActions中。然后判断如果   mPendingActions长度为1.则用handler执行mExecCommit。
mExecCommit是一个自定义的runnable。

    Runnable mExecCommit = new Runnable() {
            @Override
            public void run() {
                execPendingActions();
            }
        };


        /**
           * Only call from main thread!
           */
          public boolean execPendingActions() {
             //
              if (mExecutingActions) {
                  throw new IllegalStateException("Recursive entry to executePendingTransactions");
              }
              //必须在主线程执行
              if (Looper.myLooper() != mHost.getHandler().getLooper()) {
                  throw new IllegalStateException("Must be called from main thread of process");
              }

              boolean didSomething = false;

              //下面这个循环所做的就是将mPendingActions中所有的runnable执行。
              //mPendingActions中添加的runnable都是BackStackRecord对象
              while (true) {
                  int numActions;

                  synchronized (this) {
                      if (mPendingActions == null || mPendingActions.size() == 0) {
                          break;
                      }

                      numActions = mPendingActions.size();
                      if (mTmpActions == null || mTmpActions.length < numActions) {
                          mTmpActions = new Runnable[numActions];
                      }
                      mPendingActions.toArray(mTmpActions);
                      mPendingActions.clear();
                      mHost.getHandler().removeCallbacks(mExecCommit);
                  }

                  mExecutingActions = true;
                  for (int i=0; i<numActions; i++) {
                      mTmpActions[i].run();
                      mTmpActions[i] = null;
                  }
                  mExecutingActions = false;
                  didSomething = true;
              }

              if (mHavePendingDeferredStart) {
                  boolean loadersRunning = false;
                  for (int i=0; i<mActive.size(); i++) {
                      Fragment f = mActive.get(i);
                      if (f != null && f.mLoaderManager != null) {
                          loadersRunning |= f.mLoaderManager.hasRunningLoaders();
                      }
                  }
                  if (!loadersRunning) {
                      mHavePendingDeferredStart = false;
                      startPendingDeferredFragments();
                  }
              }
              return didSomething;
          }



我们来看下BackStackRecord的run方法。

public void run() {
       if (FragmentManagerImpl.DEBUG) Log.v(TAG, "Run: " + this);

       if (mAddToBackStack) {
           if (mIndex < 0) {
               throw new IllegalStateException("addToBackStack() called after commit()");
           }
       }
       //mAddToBackStack为false时，该函数会直接return
       bumpBackStackNesting(1);

       TransitionState state = null;
       SparseArray<Fragment> firstOutFragments = null;
       SparseArray<Fragment> lastInFragments = null;
       //这里先不分析
       if (Build.VERSION.SDK_INT >= 21) {
           firstOutFragments = new SparseArray<Fragment>();
           lastInFragments = new SparseArray<Fragment>();

           calculateFragments(firstOutFragments, lastInFragments);

           state = beginTransition(firstOutFragments, lastInFragments, false);
       }

       int transitionStyle = state != null ? 0 : mTransitionStyle;
       int transition = state != null ? 0 : mTransition;
       Op op = mHead;
       //开始遍历队列，我们刚刚执行了一次add方法，所以队列中只有一个元素，其cmd变量为OP_ADD
       while (op != null) {
           int enterAnim = state != null ? 0 : op.enterAnim;
           int exitAnim = state != null ? 0 : op.exitAnim;
           switch (op.cmd) {
               case OP_ADD: {
                   Fragment f = op.fragment;
                   f.mNextAnim = enterAnim;
                   //执行FragmentManager的addFragment方法
                   mManager.addFragment(f, false);
               } break;

              ...
               default: {
                   throw new IllegalArgumentException("Unknown cmd: " + op.cmd);
               }
           }

           op = op.next;
       }


       mManager.moveToState(mManager.mCurState, transition, transitionStyle, true);

       if (mAddToBackStack) {
           mManager.addBackStackState(this);
       }

      }



     public void addFragment(Fragment fragment, boolean moveToStateNow) {
     //moveToStateNow传入的是false
            //mAdded存的是所有通过add方法传递进来的fragment
            if (mAdded == null) {
                mAdded = new ArrayList<Fragment>();
            }
            if (DEBUG) Log.v(TAG, "add: " + fragment);
            //makeActive方法中将fragment放入mActive链表

            makeActive(fragment);
            //fragment
            if (!fragment.mDetached) {
                if (mAdded.contains(fragment)) {
                    throw new IllegalStateException("Fragment already added: " + fragment);
                }
                mAdded.add(fragment);
                fragment.mAdded = true;
                fragment.mRemoving = false;
                if (fragment.mHasMenu && fragment.mMenuVisible) {
                    mNeedMenuInvalidate = true;
                }
                //这里不执行
                if (moveToStateNow) {
                    moveToState(fragment);
                }
            }
        }

addFragment执行结束后会跳出循环，执行下面的

       mManager.moveToState(mManager.mCurState, transition, transitionStyle, true);


       void moveToState(int newState, int transit, int transitStyle, boolean always) {
            if (mActivity == null && newState != Fragment.INITIALIZING) {
                throw new IllegalStateException("No activity");
            }

            if (!always && mCurState == newState) {
                return;
            }

            mCurState = newState;
            if (mActive != null) {
                boolean loadersRunning = false;
                for (int i=0; i<mActive.size(); i++) {
                    Fragment f = mActive.get(i);
                    if (f != null) {
                        moveToState(f, newState, transit, transitStyle, false);
                        if (f.mLoaderManager != null) {
                            loadersRunning |= f.mLoaderManager.hasRunningLoaders();
                        }
                    }
                }

                if (!loadersRunning) {
                    startPendingDeferredFragments();
                }

                if (mNeedMenuInvalidate && mActivity != null && mCurState == Fragment.RESUMED) {
                    mActivity.supportInvalidateOptionsMenu();
                    mNeedMenuInvalidate = false;
                }
            }
        }



        void moveToState(Fragment f, int newState, int transit, int transitionStyle,
                  boolean keepActive) {


                  //newState 传递的是fragmentManager的mCurState属性。 下面会具体讲下这个属性
                  //transit和transitionStyle均为0 keepActive为false

              // Fragments that are not currently added will sit in the onCreate() state.
              if ((!f.mAdded || f.mDetached) && newState > Fragment.CREATED) {
                  newState = Fragment.CREATED;
              }
              if (f.mRemoving && newState > f.mState) {
                  // While removing a fragment, we can't change it to a higher state.
                  newState = f.mState;
              }
              // Defer start if requested; don't allow it to move to STARTED or higher
              // if it's not already started.
              if (f.mDeferStart && f.mState < Fragment.STARTED && newState > Fragment.STOPPED) {
                  newState = Fragment.STOPPED;
              }

              if (f.mState < newState) {
              //会走这个分支
                  // For fragments that are created from a layout, when restoring from
                  // state we don't want to allow them to be created until they are
                  // being reloaded from the layout.
                  if (f.mFromLayout && !f.mInLayout) {
                      return;
                  }
                  if (f.mAnimatingAway != null) {
                      // The fragment is currently being animated...  but!  Now we
                      // want to move our state back up.  Give up on waiting for the
                      // animation, move to whatever the final state should be once
                      // the animation is done, and then we can proceed from there.
                      f.mAnimatingAway = null;
                      moveToState(f, f.mStateAfterAnimating, 0, 0, true);
                  }
                  switch (f.mState) {
                      case Fragment.INITIALIZING:
                          if (DEBUG) Log.v(TAG, "moveto CREATED: " + f);
                          //f.mSavedFragmentState为null 这里的代码不会执行
                          if (f.mSavedFragmentState != null) {
                              f.mSavedFragmentState.setClassLoader(mActivity.getClassLoader());
                              f.mSavedViewState = f.mSavedFragmentState.getSparseParcelableArray(
                                      FragmentManagerImpl.VIEW_STATE_TAG);
                              f.mTarget = getFragment(f.mSavedFragmentState,
                                      FragmentManagerImpl.TARGET_STATE_TAG);
                              if (f.mTarget != null) {
                                  f.mTargetRequestCode = f.mSavedFragmentState.getInt(
                                          FragmentManagerImpl.TARGET_REQUEST_CODE_STATE_TAG, 0);
                              }
                              f.mUserVisibleHint = f.mSavedFragmentState.getBoolean(
                                      FragmentManagerImpl.USER_VISIBLE_HINT_TAG, true);
                              if (!f.mUserVisibleHint) {
                                  f.mDeferStart = true;
                                  if (newState > Fragment.STOPPED) {
                                      newState = Fragment.STOPPED;
                                  }
                              }
                          }
                          //设置fragment相关信息
                          f.mActivity = mActivity;
                          f.mParentFragment = mParent;
                          f.mFragmentManager = mParent != null
                                  ? mParent.mChildFragmentManager : mActivity.mFragments;
                          f.mCalled = false;
                          //执行onAttach
                          f.onAttach(mActivity);
                          if (!f.mCalled) {
                              throw new SuperNotCalledException("Fragment " + f
                                      + " did not call through to super.onAttach()");
                          }
                          if (f.mParentFragment == null) {
                              mActivity.onAttachFragment(f);
                          }
                          //mRetaining为true代表该fragment之前被保存过，比如说activity屏幕选择时，如果设置了setRetainInstance（true）就不会销毁fragment，而是把
                          //它保存下来，因为没有调用destory，所以也不用调用performCreate方法
                          if (!f.mRetaining) {
                              f.performCreate(f.mSavedFragmentState);
                          }
                          f.mRetaining = false;
                          //mFromLayout代表该fragment是不是从xml文件中静态实例化的，这里我们是动态添加的，所以是false，不会执行下面的代码
                          if (f.mFromLayout) {
                              // For fragments that are part of the content view
                              // layout, we need to instantiate the view immediately
                              // and the inflater will take care of adding it.
                              f.mView = f.performCreateView(f.getLayoutInflater(
                                      f.mSavedFragmentState), null, f.mSavedFragmentState);
                              if (f.mView != null) {
                                  f.mInnerView = f.mView;
                                  f.mView = NoSaveStateFrameLayout.wrap(f.mView);
                                  if (f.mHidden) f.mView.setVisibility(View.GONE);
                                  f.onViewCreated(f.mView, f.mSavedFragmentState);
                              } else {
                                  f.mInnerView = null;
                              }
                          }
                    //注意 这里没有break 所以会继续往下执行
                  case Fragment.CREATED:
                   if (newState > Fragment.CREATED) {
                       if (DEBUG) Log.v(TAG, "moveto ACTIVITY_CREATED: " + f);
                       if (!f.mFromLayout) {
                       //会走这里的分支
                           ViewGroup container = null;
                           //这里的f.mContainerId就是我们执行add方法传递过来的containerViewId
                           if (f.mContainerId != 0) {
                           mContainer是一个FragmentContainer对象，它的findViewById方法里面调用的是FragmentManager所在activity的findViewById方法
                               container = (ViewGroup)mContainer.findViewById(f.mContainerId);

                               if (container == null && !f.mRestored) {
                                   throwException(new IllegalArgumentException(
                                           "No view found for id 0x"
                                           + Integer.toHexString(f.mContainerId) + " ("
                                           + f.getResources().getResourceName(f.mContainerId)
                                           + ") for fragment " + f));
                               }
                           }
                           f.mContainer = container;
                           //这里会执行performCreateView方法，performCreateView返回的是Fragment OnCreateView方法返回的View
                           f.mView = f.performCreateView(f.getLayoutInflater(
                                   f.mSavedFragmentState), container, f.mSavedFragmentState);
                           if (f.mView != null) {
                           //mInnerView代表的是在保存与/恢复状态时要保存/恢复的view 这里把OnCreateView方法返回的View赋值给它
                               f.mInnerView = f.mView;
                               //这里将mView添加到了一个NoSaveStateFrameLayout中然后又赋值给mView
                               //NoSaveStateFrameLayout继承自Framelayout，官方对其描述如下：
                               /**
                                 * Pre-Honeycomb versions of the platform don't have {@link View#setSaveFromParentEnabled(boolean)},
                                 * so instead we insert this between the view and its parent.
                                 */
                              //对于这个wrap 我们不用care
                               f.mView = NoSaveStateFrameLayout.wrap(f.mView);

                               if (container != null) {
                                //fragment出现时的动画  我们没有设置 所以为null
                                   Animation anim = loadAnimation(f, transit, true,
                                           transitionStyle);
                                   if (anim != null) {
                                       f.mView.startAnimation(anim);
                                   }
                                   //将fragment的onCreateView返回的View（被wrap过）添加到了我们指定的view容器中去
                                   container.addView(f.mView);
                               }
                               if (f.mHidden) f.mView.setVisibility(View.GONE);
                               //添加完成后 执行fragment的onViewCreated方法
                               f.onViewCreated(f.mView, f.mSavedFragmentState);
                           } else {
                               f.mInnerView = null;
                           }
                       }
                       //performActivityCreated中会调用fragment的onActivityCreated方法
                       f.performActivityCreated(f.mSavedFragmentState);
                       if (f.mView != null) {
                       //调用fragment的restoreViewState方法
                           f.restoreViewState(f.mSavedFragmentState);
                       }
                       f.mSavedFragmentState = null;
                   }
                   //注意 这里也没有break
               case Fragment.ACTIVITY_CREATED:
               case Fragment.STOPPED:
                   if (newState > Fragment.STOPPED) {
                       if (DEBUG) Log.v(TAG, "moveto STARTED: " + f);
                       //执行fragment的onStart方法
                       f.performStart();
                   }
               case Fragment.STARTED:
                   if (newState > Fragment.STARTED) {
                       if (DEBUG) Log.v(TAG, "moveto RESUMED: " + f);
                       f.mResumed = true;
                        //执行fragment的onResume方法
                       f.performResume();
                       f.mSavedFragmentState = null;
                       f.mSavedViewState = null;

                  }
                }

              } else if (f.mState > newState) {
              //如果framnet现在的状态要大于FragemntManager的状态，比如说activity销毁时，会将状态从5回退到0。原理与上面的分支差不多
              switch (f.mState) {
                case Fragment.RESUMED:
                    if (newState < Fragment.RESUMED) {
                        if (DEBUG) Log.v(TAG, "movefrom RESUMED: " + f);
                        f.performPause();
                        f.mResumed = false;
                    }
                case Fragment.STARTED:
                    if (newState < Fragment.STARTED) {
                        if (DEBUG) Log.v(TAG, "movefrom STARTED: " + f);
                        f.performStop();
                    }
                case Fragment.STOPPED:
                    if (newState < Fragment.STOPPED) {
                        if (DEBUG) Log.v(TAG, "movefrom STOPPED: " + f);
                        f.performReallyStop();
                    }
                case Fragment.ACTIVITY_CREATED:
                    if (newState < Fragment.ACTIVITY_CREATED) {
                        if (DEBUG) Log.v(TAG, "movefrom ACTIVITY_CREATED: " + f);
                        if (f.mView != null) {
                            // Need to save the current view state if not
                            // done already.
                            if (!mActivity.isFinishing() && f.mSavedViewState == null) {
                                saveFragmentViewState(f);
                            }
                        }
                        f.performDestroyView();
                        if (f.mView != null && f.mContainer != null) {
                            Animation anim = null;
                            if (mCurState > Fragment.INITIALIZING && !mDestroyed) {
                                anim = loadAnimation(f, transit, false,
                                        transitionStyle);
                            }
                            if (anim != null) {
                                final Fragment fragment = f;
                                f.mAnimatingAway = f.mView;
                                f.mStateAfterAnimating = newState;
                                anim.setAnimationListener(new AnimationListener() {
                                    @Override
                                    public void onAnimationEnd(Animation animation) {
                                        if (fragment.mAnimatingAway != null) {
                                            fragment.mAnimatingAway = null;
                                            moveToState(fragment, fragment.mStateAfterAnimating,
                                                    0, 0, false);
                                        }
                                    }
                                    @Override
                                    public void onAnimationRepeat(Animation animation) {
                                    }
                                    @Override
                                    public void onAnimationStart(Animation animation) {
                                    }
                                });
                                f.mView.startAnimation(anim);
                            }
                            f.mContainer.removeView(f.mView);
                        }
                        f.mContainer = null;
                        f.mView = null;
                        f.mInnerView = null;
                    }
                case Fragment.CREATED:
                    if (newState < Fragment.CREATED) {
                        if (mDestroyed) {
                            if (f.mAnimatingAway != null) {
                                // The fragment's containing activity is
                                // being destroyed, but this fragment is
                                // currently animating away.  Stop the
                                // animation right now -- it is not needed,
                                // and we can't wait any more on destroying
                                // the fragment.
                                View v = f.mAnimatingAway;
                                f.mAnimatingAway = null;
                                v.clearAnimation();
                            }
                        }
                        if (f.mAnimatingAway != null) {
                            // We are waiting for the fragment's view to finish
                            // animating away.  Just make a note of the state
                            // the fragment now should move to once the animation
                            // is done.
                            f.mStateAfterAnimating = newState;
                            newState = Fragment.CREATED;
                        } else {
                            if (DEBUG) Log.v(TAG, "movefrom CREATED: " + f);
                            if (!f.mRetaining) {
                                f.performDestroy();
                            }

                            f.mCalled = false;
                            f.onDetach();
                            if (!f.mCalled) {
                                throw new SuperNotCalledException("Fragment " + f
                                        + " did not call through to super.onDetach()");
                            }
                            if (!keepActive) {
                                if (!f.mRetaining) {
                                    makeInactive(f);
                                } else {
                                    f.mActivity = null;
                                    f.mParentFragment = null;
                                    f.mFragmentManager = null;
                                    f.mChildFragmentManager = null;
                                }
                            }
                        }
                    }
            }

                  }
              }
              //fragment的状态设置为newState 即RESUMED
              f.mState = newState;
          }


这个moveToState方法很长，是整个FragmentManager对Fragment管理最核心的一部分，fragment各个生命周期调用也贯穿在这个方法里面。

这个方法的进去会将f.mState（即fragment当前状态）与目标状态newState（传递进来的是FragmentManager的mCurState，即FragmentManager当前状态）进行比较。
f.mState(0) < newState(5)，则fragment需要从状态0变化到状态5，需要经历INITIALIZING(0)、CREATED(1)、ACTIVITY_CREATED(2)、STOPPED(3)、STARTED(4)，最后赋值为(5)，
要注意这里的switch中是没有break的（因为没有注意到这点，这段代码看了很久都没看懂。。。感觉google在这里的注释提醒一下
)所以代码会顺序执行。同时也会调用对应的生命周期方法。


我们可以看到这里依次调用了Fragmnt的几个生命周期方法：

onAttach->onCreate->onCreateView->onViewCreated->onActivityCreated->restoreViewState->onStart->onResume

 到这里我们就成功的将一个fragment添加到FrgamentManager中了。
我们在之前提出了一个疑问，就是commit时并不是立即将fragment添加到视图上的。

现在我们知道真正添加到Fragment方法到视图上，并执行其生命周期的是moveToState方法。
 往上回溯，moveToState方法是在execPendingActions遍历所有指令（mPendingActions）时执行的。
 而execPendingActions则是在enqueueAction中push到主线程handler中执行的。
 因为moveToState这个真正调用Fragment生命周期的方法是被放到handler中执行的，所以commit不是及时生效的。

另外，还有一点可能大家会有疑惑，就是传给newState的mCurState代表的是什么？
mCurstate代表的是FragmentManager的状态，其初值为Fragment.INITIALIZING。
mCurstate反应的是FragmentManagaer所在activity的状态，比如说在FragmentActivity的OnCrate中会把mCurState改为Fragment.CREATED：

    //android.support.v4.app.FragmentActivity

    @Override
       protected void onCreate(Bundle savedInstanceState) {
           mFragments.attachActivity(this, mContainer, null);
           // Old versions of the platform didn't do this!
           if (getLayoutInflater().getFactory() == null) {
               getLayoutInflater().setFactory(this);
           }

           super.onCreate(savedInstanceState);

          ...

           //dispatchCreate会把mCurState改为Fragment.CREATED
          mFragments.dispatchCreate()
       }

 在FragmentActivity的其他几个生命周期事件中也会更改mCurstate的值，有兴趣的同学可以自己去看看，这里就不细讲了


看到这里，相信你对FragmentManager对Frament的管理策略也有所了解了。如果你还是感到很迷惑，那建议你对照着本文自己看看源码。
下一篇文章将会在本文的基础上对FragmentTransaction的remove，replace，attach等方法剖析。
