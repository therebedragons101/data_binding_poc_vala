bin_PROGRAMS = data_binding_poc_vala

data_binding_poc_vala_SOURCES = \
	config.vapi \
	common/compare_data_by.vala \
	common/delegates.vala \
	common/weak_reference_t.vala \
	common/strict_weak_reference_t.vala \
	common/object_array_t.vala \
	common/unique_by_properties.vala \
	contracts/custom_binding_source_data_t.vala \
	contracts/custom_property_notification_binding_source.vala \
	contracts/consts.vala \
	contracts/binding_value_objects.vala \
	contracts/binding_pointer_update_type.vala \
	contracts/binding_reference_type.vala \
	contracts/custom_binding_source_value.vala \
	contracts/binding_pointer.vala \
	contracts/delegates.vala \
	contracts/methods.vala \
	contracts/binding_information_reference.vala \
	contracts/contract_storage.vala \
	contracts/pointer_array.vala \
	contracts/contract_change_type.vala \
	contracts/custom_binding_source_state.vala \
	contracts/contract_array.vala \
	contracts/binding_state_objects.vala \
	contracts/binding_group.vala \
	contracts/binding_information.vala \
	contracts/binding_information_interface.vala \
	contracts/pointer_storage.vala \
	contracts/binding_suspension_group.vala \
	contracts/binding_contract.vala \
	contracts/binding_pointer_from_property_value.vala \
	property/key_value_pair_k_v.vala \
	property/binder.vala \
	property/master_slave_array_mk_k_v.vala \
	property/bind_flags.vala \
	property/property_binding.vala \
	property/delegates.vala \
	property/key_value_array_k_v.vala \
	property/data_flood_detection.vala \
	property/alias_array.vala \
	property/property_alias.vala \
	property/binding_interface.vala \
	main.vala

data_binding_poc_vala_CFLAGS = \
	-DDATA_DIRECTORY=\"$(datadir)/data_binding_poc_vala\" \
	$(data_binding_poc_vala_U_CFLAGS)

data_binding_poc_vala_VALAFLAGS = \
	--pkg gtk+-3.0 \
	--target-glib $(GLIB_REQUIRED)

data_binding_poc_vala_LDADD = \
	$(data_binding_poc_vala_U_LIBS)

