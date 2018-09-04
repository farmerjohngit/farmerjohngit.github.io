hexo g 
rm -rf /Users/zhangzunchang/new_blog_public/*
cp -rf /Users/zhangzunchang/Documents/blog/public/ /Users/zhangzunchang/new_blog_public
cd /Users/zhangzunchang/new_blog_public
git add -A
git commit -m \"update\" 
git remote add deploy root@47.91.221.198:/root/blog_update
git push deploy master --force
#send "Farmercoding992#\r"
