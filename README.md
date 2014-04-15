UnfuckBank
==========

This is a hacky Elder Scrolls Online addon to restack items in the Guild Bank.

For some reason sometimes when you deposit items in the GB when there are already items the same there that could be stacked together it uses a new GB slot. This addon finds items in the GB that are taking up more slots than necessary, withdraws them into your backpack where they are automatically re-stacked, then deposits them back in the GB.

I'm sure Zenimax will fix this issue before long, but this was irritating me and it seemed like a good way to try out the ESO API (FYI it kinda sucks).

**Note: This is not tested very well, but it kinda works for me. If it causes your cool purplez to evaporate, don't blame me.**

Usage
-----

1. Install the addon like any other

2. Open your Guild Bank

3. Re-stack with the command:

		/unfuck

Caveats
-------

If you already have some quantity of an item that is getting re-stacked in your inventory it will end up in the GB with the rest.

Todo
----

Might add support for the personal bank as well, but this will do for now and Zenimax will probably fix the issue soon (hopefully).