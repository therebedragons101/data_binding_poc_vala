bin_PROGRAMS = data_binding_poc_vala

data_binding_poc_vala_SOURCES = \
	config.vapi \
	convenience_classes.vala \
	binding_contract.vala \
	property_binding.vala \
	main.vala

data_binding_poc_vala_CFLAGS = \
	-DDATA_DIRECTORY=\"$(datadir)/data_binding_poc_vala\" \
	$(data_binding_poc_vala_U_CFLAGS)

data_binding_poc_vala_VALAFLAGS = \
	--pkg gtk+-3.0 \
	--target-glib $(GLIB_REQUIRED)

data_binding_poc_vala_LDADD = \
	$(data_binding_poc_vala_U_LIBS)

