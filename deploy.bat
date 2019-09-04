
echo "\nDeploying updates to GitHub...\n"

# Build the project.
..\hugo\hugo.exe -t hyde

# Go To Public folder
cd public

# Add changes to git.
git add .

# Commit changes.
git commit -m "Deployed %date%"

# Push source and build repos.
git push origin master