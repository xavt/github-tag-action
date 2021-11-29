#!/bin/bash

set -o pipefail

# config
default_semvar_bump=${DEFAULT_SEMVAR_BUMP:-patch}
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
suffix=${PRERELEASE_SUFFIX:-beta}
verbose=${VERBOSE:-true}
filename=${VERSION_FILENAME:-VERSION}
bundle=${BUNDLE:-false}
bundler_version=${BUNDLER_VERSION:-2.2.21}
bundle_path=${BUNDLE_PATH:-vendor/bundle}

cd ${GITHUB_WORKSPACE}/${source}

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_SEMVAR_BUMP: ${default_semvar_bump}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"
echo -e "\tFILENAME: ${filename}"
echo -e "\tBUNDLE: ${bundle}"
echo -e "\tBUNDLER_VERSION: ${bundler_version}"
echo -e "\tBUNDLE_PATH: ${bundle_path}"

current_branch=$(git rev-parse --abbrev-ref HEAD)

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${current_branch}"
    if [[ "${current_branch}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

# fetch tags
git fetch --tags

# get latest tag that looks like a semver (with or without v)
case "$tag_context" in
    *repo*) 
        tag=$(git for-each-ref --sort=-v:refname --format '%(refname:lstrip=2)' | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+$" | head -n1)
        pre_tag=$(git for-each-ref --sort=-v:refname --format '%(refname:lstrip=2)' | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+(-$suffix\.[0-9]+)?$" | head -n1)
        ;;
    *branch*) 
        tag=$(git tag --list --merged HEAD --sort=-v:refname | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+$" | head -n1)
        pre_tag=$(git tag --list --merged HEAD --sort=-v:refname | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+(-$suffix\.[0-9]+)?$" | head -n1)
        ;;
    * ) echo "Unrecognised context"; exit 1;;
esac

# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty='%B')
    tag="$initial_version"
    pre_tag="$initial_version"
else
    log=$(git log $tag..HEAD --pretty='%B')
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    exit 0
fi

# echo log if verbose is wanted
if $verbose
then
  echo $log
fi

case "$default_semvar_bump" in
    *major* ) new=$(semver -i major $tag); part="major";;
    *minor* ) new=$(semver -i minor $tag); part="minor";;
    *patch* ) new=$(semver -i patch $tag); part="patch";;
    * ) echo "Default bump was not set or an invalid value. Skipping..."; echo ::set-output name=new_tag::$tag; echo ::set-output name=tag::$tag; exit 0 

esac

if $pre_release
then
    # Already a prerelease available, bump it
    if [[ "$pre_tag" == *"$new"* ]]; then
        new=$(semver -i prerelease $pre_tag --preid $suffix); part="pre-$part"
    else
        new="$new-$suffix.1"; part="pre-$part"
    fi
fi

echo $part

# did we get a new tag?
if [ ! -z "$new" ]
then
	# prefix with 'v'
	if $with_v
	then
		new="v$new"
	fi
fi

if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

if $pre_release
then
    echo -e "Bumping tag ${pre_tag}. \n\tNew tag ${new}"
else
    echo -e "Bumping tag ${tag}. \n\tNew tag ${new}"
fi

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=part::$part

# use dry run to determine the next tag
if $dryrun
then
    echo ::set-output name=tag::$tag
    exit 0
fi 

echo ::set-output name=tag::$new

# Bump version file
git remote add github "https://$GITHUB_ACTOR:$GITHUB_TOKEN@github.com/$GITHUB_REPOSITORY.git"
git pull github ${GITHUB_REF} --ff-only

test -f $filename || touch $filename
echo $new > $filename
export COMMIT_TITLE=$new

git config --global user.email "gha@github.co"
git config --global user.name "BOXT Tagger"

# echo log if verbose is wanted
if $bundle
then
  gem install bundler:$bundler_version
  bundle config path $bundle_path
  bundle install --jobs 4 --retry 3
  git add Gemfile.lock
fi

git add filename
git commit -m "Bump version to $COMMIT_TITLE"

git push github HEAD:${GITHUB_REF}

commit=$(git rev-parse HEAD)

# create local git tag
git tag $new

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

git_refs_response=$(
curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
)

git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

echo "::debug::${git_refs_response}"
if [ "${git_ref_posted}" = "refs/tags/${new}" ]; then
  exit 0
else
  echo "::error::Tag was not created properly."
  exit 1
fi
