
HUGO ?= hugo

CONTENT_PATH = "content/posts"

.PHONY: server
server:
	# server with draft contents
	$(HUGO) server -D

NAME ?=
.PHONY: new
new:
	$(HUGO) new content $(CONTENT_PATH)/$(NAME).md
