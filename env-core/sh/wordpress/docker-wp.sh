#!/bin/bash

set -o errexit #to stop the script when an error occurs
set -o pipefail

docker_wp_create () {
    if [ "$( docker ps --format '{{.Names}}' | grep -P '(^)nginx-proxy($)' )" ];
    then
        set_setup_type
        check_domain_exists

        if [[ $DOMAIN_EXISTS == 0 ]];
        then
            check_all_data
            if [ "$( docker image ls | grep -P '(^|_)'$DOCKER_CONTAINER_WP'(?=\s|$)' )" ] && [ "$( docker volume ls --format '{{.Name}}' | grep -P '(^|_)'$DOCKER_VOLUME_DB'($)' )" ];
            then
                ECHO_SUCCESS "Site image and volume found"
                [ "$( docker ps --format '{{.Names}}' | grep -P "(^|\s)\'$DOCKER_CONTAINER_WP'(?=\s|$)" )" ] && ECHO_ERROR "Containers already running for this domain" && exit;
                [ -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ] && ECHO_ERROR "Docker-compose file present, you can start local site again by choosing 3" && exit;
            else
                if [ -f "./env-core/templates/wordpress/docker-compose.example.com.yml" ];
                then
                    if [ ! -d $PROJECT_ROOT_DIR ];
                    then
                        ECHO_INFO "Setting up Docker containers for $DOMAIN_FULL"

                        #GET PORT
                        get_unique_port

                        if [[ $PORT && $DOMAIN_NAME && $DB_NAME ]];
                        then
                            echo "$PORT | https | $DOMAIN_NAME | $DOMAIN_FULL | $DB_NAME |" >> "$FILE_INSTANCES"
                        fi

                        mkdir -p $PROJECT_DOCKER_DIR

                        #Choose needed Dockerfile
                        if [[ $COMPOSER == "no" ]];
                        then
                           cp ./env-core/templates/wordpress/Dockerfile-template $PROJECT_DOCKER_DIR/Dockerfile
                        else
                           cp ./env-core/templates/wordpress/Dockerfile-composer $PROJECT_DOCKER_DIR/Dockerfile
                        fi

                        sed -i -e 's/{WP_VERSION}/'$WP_VERSION'/g' $PROJECT_DOCKER_DIR/Dockerfile
                        sed -i -e 's/{PHP_VERSION}/'$PHP_VERSION'/g' $PROJECT_DOCKER_DIR/Dockerfile

                        cp ./env-core/templates/wordpress/docker-compose.example.com.yml $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml
                        sed -i -e 's/{DOMAIN_NAME}/'$DOMAIN_NAME'/g' $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml

                        #Replace Volumes from 'wp-content' to 'wp-core' files SETUP_TYPE=beetroot
                        [[ "$SETUP_TYPE" == 3 ]] && sed -i -e 's/wp-content\///g' $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml

                        cp ./env-core/templates/wordpress/php.conf.ini $PROJECT_DOCKER_DIR/php.conf.ini

                        env_file_load

                        ECHO_GREEN "Docker compose file set and container can be built and started"
                        echo "Starting Container"
                        docker-compose -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml up -d --build

                        ECHO_SUCCESS "Containers Started"

                        setup_hosts_file add
                        fix_permissions
                        notice_windows_host add
                        docker_wp_restart

                        wp_core_install
                        wp_remove_default_content
                        
                        #clone from repo
                        while true; do
                            EMPTY_LINE
                            read -rp "$(ECHO_YELLOW "Start Clone?") Y/n " yn

                            case $yn in
                            [Yy]*)
                                git_clone_repo
                                break
                            ;;
                            [Nn]*)
                                break
                                ;;

                            *) echo "Please answer yes or no" ;;
                            esac
                        done

                        # Print for user project info
                        EMPTY_LINE
                        ECHO_INFO "Project variables:"
                        notice_project_vars

                        # COMPOSER_ISSUE exists
                        notice_composer

                    else
                        ECHO_YELLOW "Wordpress for $DOMAIN_FULL is already created"
                        if [ -d $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ];
                        then
                            ECHO_YELLOW "Docker File already setup"
                            if [ "$( docker ps --format '{{.Names}}' | grep -P '(^)'$DOCKER_CONTAINER_WP'($)' )" ]
                            then 
                                ECHO_ERROR "Container running already"
                                exit;
                            else
                                ECHO_ERROR "Container not started"
                                exit;
                            fi
                        else
                            ECHO_ERROR "Docker-compose file not found, either delete folder and build again"
                            exit;
                        fi
                    fi
                else
                    ECHO_ERROR "Docker compose file for wordpress not here"
                    echo "Make sure file is not deleted"
                    if [ "$(git status| grep templates/wordpress/docker-compose.example.com.yml)" ]
                    then
                        echo "File has been deleted"
                        git checkout -- templates/wordpress/docker-compose.example.com.yml
                        echo "File has been restored, run script again"
                        exit;
                    else
                        ECHO_ERROR "Recheck why docker-compose is not in folder"
                        exit;
                    fi
                fi
            fi 
        fi
    else
        ECHO_ERROR "Nginx container not running"
    fi
}

docker_wp_start () {
    stopped_projects_list "======== START project ========"
    get_project_dir "skip_question"

    if [ "$( docker ps --format '{{.Names}}' | grep -P '(^)'$DOCKER_CONTAINER_WP'($)' )" ];
    then
        ECHO_WARN_RED "Containers already running for this domain"
        exit;
    else
        if [ "$( docker image ls | grep -P '(^|_)'$DOCKER_CONTAINER_WP'(?=\s|$)' )" ] && [ "$( docker volume ls --format '{{.Name}}' | grep -P '(^|_)'$DOCKER_VOLUME_DB'($)' )" ];
        then
            ECHO_SUCCESS "Site image and volume found"

            if [ -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ];
            then
                ECHO_YELLOW "Starting docker containers for this site"

                docker-compose -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml up -d

                ECHO_GREEN "Restarted now."
                docker_nginx_restart
                
                fix_permissions
            else
                ECHO_ERROR "Docker-compose file for this site was not found"
                ECHO_ERROR "Cannot restart site, in this case delete and start again"
            fi
        else
            # In case the docker images were deleted
            ECHO_ERROR "Site image or volume was not found"
            ECHO_YELLOW "Checking for Docker-compose file exist"
            if [ -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ];
            then
                echo "Starting Container"
                docker-compose -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml up -d
            else
                ECHO_ERROR "Docker-compose file not found"
                exit;
            fi
        fi
    fi
}


docker_wp_stop () {
    get_project_dir "skip_question"

    if [ "$( docker ps --format '{{.Names}}' | grep -P '(^)'$DOCKER_CONTAINER_WP'($)' )" ];
    then
        
        if [ -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ];
        then
            docker-compose -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml down
        fi

        docker_nginx_restart

        ECHO_SUCCESS "Docker container $DOMAIN_FULL stopped"

    else
        ECHO_ERROR "Docker container for this site does not exist"
    fi
}

docker_wp_restart () {
    [[ "$DOMAIN_NAME" == '' ]] && running_projects_list "======= RESTART project ======="

    get_project_dir "skip_question"

    if [ "$( docker ps --format '{{.Names}}' | grep -P '(^)'$DOCKER_CONTAINER_WP'($)' )" ];
    then
        [ -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ] && docker-compose -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml restart
        docker_nginx_restart
    else
        ECHO_ERROR "Docker container for this site does not exist"
    fi
}

docker_wp_delete () {
    get_existing_domains "======== DELETE project ======="

    get_project_dir "skip_question"

    if [ -d $PROJECT_ROOT_DIR ];
    then
        EMPTY_LINE
        ECHO_ATTENTION "You can't restore the site after it has been deleted."
        ECHO_ATTENTION "This operation will remove the localhost containers, volumes, and the WordPress core files."
        while true; do
            ECHO_WARN_YELLOW "Removing now... $DOMAIN_FULL"
            read -rp "$(ECHO_WARN_RED "Do you wish to proceed?") [Y/n] " yn
            case $yn in
                [Yy]*)
                    ECHO_YELLOW "Deleting site"
                    fix_permissions
                    docker_wp_stop
                    
                    if [ $( docker image ls --format '{{.Repository}}' | grep -P '(^|_)'$DOCKER_CONTAINER_WP'(?=\s|$)' ) ];
                    then
                        EMPTY_LINE
                        imageid=$( docker image ls --format '{{.Repository}}' | grep -P '(^|_)'$DOCKER_CONTAINER_WP'(?=\s|$)' )
                        [ -n "$imageid" ] && docker rmi "$imageid" --force && ECHO_YELLOW "Deleting images" || ECHO_WARN_YELLOW "Image not found"
                    else
                        ECHO_ERROR "Docker image does not exist"
                    fi

                    if [ $( docker volume ls --format '{{.Name}}' | grep -P '(^|_)'$DOCKER_VOLUME_DB'($)' ) ];
                    then
                        EMPTY_LINE
                        volumename=$( docker volume ls --format '{{.Name}}' | grep -P '(^|_)'$DOCKER_VOLUME_DB'($)' )
                        [ -n "$volumename" ] && docker volume rm "$volumename" && ECHO_YELLOW "Deleting Volume" || echo "Volume not found"
                    else
                        ECHO_ERROR "Docker volume does not exist"
                    fi

                    delete_site_data
                    notice_windows_host rem
                    
                    break
                    ;;
                [Nn]*) 
                    unset_variables
                    existing_site_actions
                    ;;

                *) echo "Please answer yes or no" ;;
            esac
        done
    else
        ECHO_ERROR "Site DIR does not exist: $PROJECT_ROOT_DIR"
    fi
}

docker_wp_rebuild () {
    get_existing_domains "======= REBUILD project ======="

    get_project_dir "skip_question"

    if [ -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml ];
    then
        docker-compose -f $PROJECT_DOCKER_DIR/docker-compose."$DOMAIN_NODOT".yml up -d --force-recreate --no-deps --build
    fi
}
