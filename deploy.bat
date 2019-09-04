
echo "\nDeploying updates to GitHub...\n"

REM Build the project.
..\hugo\hugo.exe -t hyde

REM Go To Public folder
cd public

REM Add changes to git.
git add .

REM Commit changes.
git commit -m "Deployed %date%"

REM Push source and build repos.
git push origin master