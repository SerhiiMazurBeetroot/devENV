#!/bin/bash

set -o errexit #to stop the script when an error occurs
set -o pipefail

clone_repo () {
    get_existing_domains

    DOMAIN_CHECK=$(awk '/'"$DOMAIN_NAME"'/{print $5}' wp-instances.log | head -n 1);
    [[ "$DOMAIN_NAME" == "$DOMAIN_CHECK" ]] && DOMAIN_EXISTS=1

    if [[ $DOMAIN_EXISTS == 1 ]];
    then
        get_project_dir "skip_question"
    
        ECHO_INFO "Getting plugins and themes from the repository"
        read -rp "Clone from repo (url): " clone
        while [ -z "$clone" ]; do 
            read -rp "Please complete the cloning path: " clone
        done

        if curl --output /dev/null --silent --head --fail -k $clone
        then
            ECHO_YELLOW "Cloning repository to temp..."
            rm -rf $PROJECT_ROOT_DIR/repository
            
            git config --global http.sslVerify false

            git clone "$clone" $PROJECT_ROOT_DIR/repository/

            if [ ! -d $PROJECT_DATABASE_DIR/ ];
            then
                ECHO_INFO "Creating DIR wp-database..."
                mkdir $PROJECT_DATABASE_DIR/
            fi

            ECHO_INFO "Please wait, copying themes and plugins..."

            if [[ -d $PROJECT_ROOT_DIR/repository/wp-content || -d $PROJECT_ROOT_DIR/repository/wp-admin || -d $PROJECT_ROOT_DIR/repository/wp-includes ]];
            then
                cp -rf  $PROJECT_ROOT_DIR/repository/. $PROJECT_ROOT_DIR/
            fi

            if [ -d $PROJECT_ROOT_DIR/repository/themes ];
            then
                cp -rf $PROJECT_ROOT_DIR/repository/themes/. $PROJECT_ROOT_DIR/wp-content/themes/
            fi

            if [ -d $PROJECT_ROOT_DIR/repository/plugins ];
            then
                cp -rf $PROJECT_ROOT_DIR/repository/plugins/. $PROJECT_ROOT_DIR/wp-content/plugins/
            fi

            if [ -d $PROJECT_ROOT_DIR/repository/uploads ];
            then
                cp -rf $PROJECT_ROOT_DIR/repository/uploads/. $PROJECT_ROOT_DIR/wp-content/uploads/
            fi

            rm -rf $PROJECT_ROOT_DIR/repository
            ECHO_YELLOW "Themes and plugins copied"

            while true; do
                EMPTY_LINE
                read -rp "$(ECHO_YELLOW "Start importing DB?") Y/n " yn

                case $yn in
                [Yy]*)
                    import_db
                    break
                ;;
                [Nn]*)
                    break
                    ;;

                *) echo "Please answer yes or no" ;;
                esac
            done
        else
            echo -e "${RED} Path is not correct"
            exit;
        fi
    else
        ECHO_ERROR "Docker container for this site does not exist"
    fi
}

get_latest_wp_version () {
    WP_LATEST_VER=$(curl -s 'https://api.github.com/repos/wordpress/wordpress/tags' | grep "name" | head -n 1 | awk '$0=$2' | awk '{gsub(/\"|\",/, ""); print}');
    export WP_LATEST_VER
}
