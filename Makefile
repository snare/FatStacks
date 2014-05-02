NAME=FatStacks
TMP_DIR=/tmp
TMP_ZIP=FatStacks.zip

all: zip

zip: 
	rm -rf $(TMP_DIR)/$(NAME)
	rm -f $(TMP_DIR)/$(TMP_ZIP)
	cp -R . $(TMP_DIR)/$(NAME)
	rm -rf $(TMP_DIR)/$(NAME)/.git
	cd $(TMP_DIR) && zip -r $(TMP_ZIP) $(NAME)
