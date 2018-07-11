title: 深入分析FragmentManager管理机制(二)
date: 2016-07-31 09:48:53
tags:
---
  
[上篇文章](http://farmercoding.win/2016/07/17/fragment/)我们分析了FragmentManager是怎样添加一个fragment的，在这篇文章中，我们将介绍attach,disatch,replace,remove等几个方法


从上篇文章我们可以知道，FragmentManager(下文简称FM)执行一个事务（FragmentTransaction),commit后会调用到  BackStackRecord(FragmentTransaction的子类)的run方法中。我们来看下这个方法
 <!-- more -->
 ```java
  
    public void run() {
        ...
        int transitionStyle = state != null ? 0 : mTransitionStyle;
        int transition = state != null ? 0 : mTransition;
        Op op = mHead;
        while (op != null) {
            int enterAnim = state != null ? 0 : op.enterAnim;
            int exitAnim = state != null ? 0 : op.exitAnim;
            switch (op.cmd) {
                case OP_ADD: {
                    Fragment f = op.fragment;
                    f.mNextAnim = enterAnim;
                    mManager.addFragment(f, false);
                } break;
                case OP_REPLACE: {
                    Fragment f = op.fragment;
                    if (mManager.mAdded != null) {
                        for (int i=0; i<mManager.mAdded.size(); i++) {
                            Fragment old = mManager.mAdded.get(i);
                            if (FragmentManagerImpl.DEBUG) Log.v(TAG,
                                    "OP_REPLACE: adding=" + f + " old=" + old);
                            if (f == null || old.mContainerId == f.mContainerId) {
                                if (old == f) {
                                    op.fragment = f = null;
                                } else {
                                    if (op.removed == null) {
                                        op.removed = new ArrayList<Fragment>();
                                    }
                                    op.removed.add(old);
                                    old.mNextAnim = exitAnim;
                                    if (mAddToBackStack) {
                                        old.mBackStackNesting += 1;
                                        if (FragmentManagerImpl.DEBUG) Log.v(TAG, "Bump nesting of "
                                                + old + " to " + old.mBackStackNesting);
                                    }
                                    mManager.removeFragment(old, transition, transitionStyle);
                                }
                            }
                        }
                    }
                    if (f != null) {
                        f.mNextAnim = enterAnim;
                        mManager.addFragment(f, false);
                    }
                } break;
                case OP_REMOVE: {
                    Fragment f = op.fragment;
                    f.mNextAnim = exitAnim;
                    mManager.removeFragment(f, transition, transitionStyle);
                } break;
                case OP_HIDE: {
                    Fragment f = op.fragment;
                    f.mNextAnim = exitAnim;
                    mManager.hideFragment(f, transition, transitionStyle);
                } break;
                case OP_SHOW: {
                    Fragment f = op.fragment;
                    f.mNextAnim = enterAnim;
                    mManager.showFragment(f, transition, transitionStyle);
                } break;
                case OP_DETACH: {
                    Fragment f = op.fragment;
                    f.mNextAnim = exitAnim;
                    mManager.detachFragment(f, transition, transitionStyle);
                } break;
                case OP_ATTACH: {
                    Fragment f = op.fragment;
                    f.mNextAnim = enterAnim;
                    mManager.attachFragment(f, transition, transitionStyle);
                } break;
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
 ```
 
 在这个方法中，OP_XXX对应的是FragmentTransaction不同的方法，如OP_ADD对应的是add方法 。上文我们已经分析过OP_ADD操作了，在这篇文章中，我们将对OP_ATTACH(attach), OP_DETACH(detach), OP_SHOW(show), OP_HIDE(hide),OP_REMOVE(remove)，等几个操作进行分析
 
 
 
 
调用到了FragmentManager的方法attachFragment
 

```java
 //OP_HIDE
    public void hideFragment(Fragment fragment, int transition, int transitionStyle) {
        if (DEBUG) Log.v(TAG, "hide: " + fragment);
        if (!fragment.mHidden) {
            fragment.mHidden = true;
            //mView是fragment onCreateView方法返回的对象的封装
            if (fragment.mView != null) {
                Animation anim = loadAnimation(fragment, transition, false,
                        transitionStyle);
                if (anim != null) {
                    fragment.mView.startAnimation(anim);
                }
                fragment.mView.setVisibility(View.GONE);
            }
            if (fragment.mAdded && fragment.mHasMenu && fragment.mMenuVisible) {
                mNeedMenuInvalidate = true;
            }
            fragment.onHiddenChanged(true);
        }
    }
```   

hideFragment比较简单，就是将fragment的mView隐藏起来
 
```
//OP_SHOW
    public void showFragment(Fragment fragment, int transition, int transitionStyle) {
        if (DEBUG) Log.v(TAG, "show: " + fragment);
        if (fragment.mHidden) {
            fragment.mHidden = false;
            if (fragment.mView != null) {
                Animation anim = loadAnimation(fragment, transition, true,
                        transitionStyle);
                if (anim != null) {
                    fragment.mView.startAnimation(anim);
                }
                fragment.mView.setVisibility(View.VISIBLE);
            }
            if (fragment.mAdded && fragment.mHasMenu && fragment.mMenuVisible) {
                mNeedMenuInvalidate = true;
            }
            fragment.onHiddenChanged(false);
        }
    }
```
showFragment刚好和hideFragment相反


```java
 //frameworks/support/v4/java/android/support/v4/app/FragmentManager.java
 
 
 //OP_REMOVE
 public void removeFragment(Fragment fragment, int transition, int transitionStyle) {
        if (DEBUG) Log.v(TAG, "remove: " + fragment + " nesting=" + fragment.mBackStackNesting);
        final boolean inactive = !fragment.isInBackStack();
        //如果当前fragment没有被mDetached或者不在回退栈中
        if (!fragment.mDetached || inactive) {
        	//mAdded 是一个链表，里面存的是当前fm中所有已经被添加的fragment
            if (mAdded != null) {
                mAdded.remove(fragment);
            }
            if (fragment.mHasMenu && fragment.mMenuVisible) {
                mNeedMenuInvalidate = true;
            }
            fragment.mAdded = false;
            fragment.mRemoving = true;
            //moveToState方法上篇文章已经介绍过，其作用是改变一个fragment的状态（fragment的各种生命周期方法也在这里被调用）。
            // 在这里将该fragment的状态变化到INITIALIZING(如果该fragment在添加时有执行addToBackStack方法，则状态变化到CREATED)
            moveToState(fragment, inactive ? Fragment.INITIALIZING : Fragment.CREATED,
                    transition, transitionStyle, false);
        }
    }
```  
在removeFragment方法中，会将fragment状态变化到INITIALIZING（假设在添加fragment时没有执行addToBackStack），在moveToState，会依次调用该fragment的如下生命周期方法：

performPause->performStop->performReallyStop()->saveFragmentViewState()->f.performDestroyView()->performDestroy()-> onDetach

这里要说下saveFragmentViewState方法，该方法会调用到fragment的minnerView（onCreateView返回的对象）的saveHierarchyState方法，saveHierarchyState该方法的作用是将view的状态保存下来，具体会保存什么状态依赖于view的各自实现

```java   
 //OP_DETACH
    public void detachFragment(Fragment fragment, int transition, int transitionStyle) {
        if (DEBUG) Log.v(TAG, "detach: " + fragment);
        if (!fragment.mDetached) {
            fragment.mDetached = true;
            if (fragment.mAdded) {
                // We are not already in back stack, so need to remove the fragment.
                if (mAdded != null) {
                    if (DEBUG) Log.v(TAG, "remove from detach: " + fragment);
                    mAdded.remove(fragment);
                }
                if (fragment.mHasMenu && fragment.mMenuVisible) {
                    mNeedMenuInvalidate = true;
                }
                fragment.mAdded = false;
                moveToState(fragment, Fragment.CREATED, transition, transitionStyle, false);
            }
        }
    }
```
在detachFragment方法中，会将fragment状态变化到CREATED，在moveToState，会依次调用该fragment的如下生命周期方法：

performPause->performStop->performReallyStop()->saveFragmentViewState()->f.performDestroyView()

detachFragment与removeFragment相比，少调用了performDestroy和onDetach两个生命周期方法，也就是说detach只会销毁fragment的视图，而remove不仅会销毁视图，而且解除fragment与当前FM的关系,以及当前activity的关系

```java
    public void attachFragment(Fragment fragment, int transition, int transitionStyle) {
        if (DEBUG) Log.v(TAG, "attach: " + fragment);
        //必须该fragment调用过detach，才会走下面这个分支
        if (fragment.mDetached) {
            fragment.mDetached = false;
            if (!fragment.mAdded) {
                if (mAdded == null) {
                    mAdded = new ArrayList<Fragment>();
                }
                if (mAdded.contains(fragment)) {
                    throw new IllegalStateException("Fragment already added: " + fragment);
                }
                if (DEBUG) Log.v(TAG, "add from attach: " + fragment);
                mAdded.add(fragment);
                fragment.mAdded = true;
                if (fragment.mHasMenu && fragment.mMenuVisible) {
                    mNeedMenuInvalidate = true;
                }
                //同addFragemt
                moveToState(fragment, mCurState, transition, transitionStyle, false);
            }
        }
    }

```
	    
	    
	    


 
