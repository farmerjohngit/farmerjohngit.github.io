hexo g 
rm -rf /Users/farmerjohn/new_blog_public/*
cp -rf /Users/farmerjohn/blog/public/ /Users/farmerjohn/new_blog_public
cd /Users/farmerjohn/new_blog_public
git add -A
git commit -m \"update\" 
git push deploy --force
#send "Farmercoding992#\r"
