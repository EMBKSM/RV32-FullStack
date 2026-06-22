# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "BTN_W" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LED_W" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SW_W" -parent ${Page_0}


}

proc update_PARAM_VALUE.BTN_W { PARAM_VALUE.BTN_W } {
	# Procedure called to update BTN_W when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BTN_W { PARAM_VALUE.BTN_W } {
	# Procedure called to validate BTN_W
	return true
}

proc update_PARAM_VALUE.LED_W { PARAM_VALUE.LED_W } {
	# Procedure called to update LED_W when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LED_W { PARAM_VALUE.LED_W } {
	# Procedure called to validate LED_W
	return true
}

proc update_PARAM_VALUE.SW_W { PARAM_VALUE.SW_W } {
	# Procedure called to update SW_W when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SW_W { PARAM_VALUE.SW_W } {
	# Procedure called to validate SW_W
	return true
}


proc update_MODELPARAM_VALUE.LED_W { MODELPARAM_VALUE.LED_W PARAM_VALUE.LED_W } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LED_W}] ${MODELPARAM_VALUE.LED_W}
}

proc update_MODELPARAM_VALUE.SW_W { MODELPARAM_VALUE.SW_W PARAM_VALUE.SW_W } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SW_W}] ${MODELPARAM_VALUE.SW_W}
}

proc update_MODELPARAM_VALUE.BTN_W { MODELPARAM_VALUE.BTN_W PARAM_VALUE.BTN_W } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BTN_W}] ${MODELPARAM_VALUE.BTN_W}
}

