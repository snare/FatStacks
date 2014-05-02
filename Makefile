TMP_DIR=/tmp/FatStacks
TMP_ZIP=/tmp/FatStacks.zip

all: zip

zip: 
	rm -rf $(TMP_DIR)
	cp -R . $(TMP_DIR)
	rm -rf $(TMP_DIR)/.git
	zip -r $(TMP_ZIP) $(TMP_DIR)
