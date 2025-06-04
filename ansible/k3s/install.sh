source .env
ansible-playbook -v -i hosts.yaml install.yaml -K  -e "aws_access_key=$AWS_ACCESS_KEY_ID aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"
