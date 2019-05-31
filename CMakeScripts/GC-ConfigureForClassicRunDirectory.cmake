function(configureForClassicRunDirectory)
    # Get the run directory
	gc_message(SECTION "Run directory setup")
	set(RUNDIR_DEFAULT "..")
	set_dynamic_default(RUNDIR DEFAULT "${RUNDIR_DEFAULT}"
		LOG RUNDIR_LOG
		IS_DIRECTORY
	)
	dump_log(RUNDIR_LOG)
	message(STATUS "Bootstrapping ${RUNDIR}")
	get_filename_component(RUNDIR "${RUNDIR}" ABSOLUTE) # Make RUNDIR an absolute path

    # Define a macro for inspecting the run directory. Inspecting the run
    # directory is how we determine which compiler definitions need to be set.
    macro(inspect_rundir VAR ID)
    execute_process(COMMAND perl ${RUNDIR}/getRunInfo ${RUNDIR} ${ID}
        OUTPUT_VARIABLE ${VAR}
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    endmacro()

    # Inspect the run directory to get the met field type and grid resolution
    inspect_rundir(RUNDIR_MET 0)
    if("${RUNDIR_MET}" STREQUAL "geosfp")
        set(RUNDIR_MET "GEOS_FP")
    elseif("${RUNDIR_MET}" STREQUAL "merra2")
        set(RUNDIR_MET "MERRA2")
    endif()
    inspect_rundir(RUNDIR_GRID 1)
    if("${RUNDIR_GRID}" STREQUAL "2x25")
        set(RUNDIR_GRID "2x2.5")
    elseif("${RUNDIR_GRID}" STREQUAL "05x0625")
        set(RUNDIR_GRID "0.5x0.625")
    elseif("${RUNDIR_GRID}" STREQUAL "025x03125")
        set(RUNDIR_GRID "0.25x0.3125")
    endif()

    # Inspect the run directory to get simulation type
    inspect_rundir(RUNDIR_SIM 2)

    # Determine the appropriate chemistry mechanism base on the simulation
    set(STANDARD_MECHS
        "standard"
        "benchmark"
        "aciduptake"
        "marinePOA"
        "masscons"
        "TransportTracers"
        "POPs"
        "CH4"
        "tagCH4"
        "tagO3"
        "tagCO"
        "tagHg"
        "CO2"
        "aerosol"
        "Hg"
        "HEMCO" # doesn't matter for the HEMCO standalone
    )
    set(TROPCHEM_MECHS
        "tropchem"
        "RRTMG"
        "TOMAS15"
        "TOMAS40"
        "complexSOA"
    )
    set(SOA_SVPOA_MECHS
        "complexSOA_SVPOA"
    )
    set(CUSTOM_MECHS
        "custom"
    )
    if("${RUNDIR_SIM}" IN_LIST STANDARD_MECHS)
        set(RUNDIR_MECH "Standard")
    elseif("${RUNDIR_SIM}" IN_LIST TROPCHEM_MECHS)
        set(RUNDIR_MECH "Tropchem")
    elseif("${RUNDIR_SIM}" IN_LIST SOA_SVPOA_MECHS)
        set(RUNDIR_MECH "SOA_SVPOA")
    elseif("${RUNDIR_SIM}" IN_LIST CUSTOM_MECHS)
        set(RUNDIR_MECH "custom")
    else()
        message(FATAL_ERROR "Unknown simulation type \"${RUNDIR_SIM}\". Cannot determine MECH.")
    endif()

    # Definitions for specific run directories
    set(TOMAS FALSE)
    if("${RUNDIR_SIM}" STREQUAL "masscons")
        target_compile_definitions(BaseTarget INTERFACE MASSCONS)
    elseif("${RUNDIR_SIM}" MATCHES "TOMAS15")
        target_compile_definitions(BaseTarget INTERFACE TOMAS TOMAS15)
        set(TOMAS TRUE)
    elseif("${RUNDIR_SIM}" MATCHES "TOMAS40")
        target_compile_definitions(BaseTarget INTERFACE TOMAS TOMAS40)
        set(TOMAS TRUE)
    endif()

    # Inspect the run directory to determine if it's a nested simulation
    inspect_rundir(RUNDIR_REGION 3)
    if("${RUNDIR_REGION}" STREQUAL "n")
        set(RUNDIR_NESTED "FALSE")
        unset(RUNDIR_REGION)
    else()
        set(RUNDIR_NESTED "TRUE")
        string(TOUPPER "${RUNDIR_REGION}" RUNDIR_REGION)
    endif()

    # Make MECH an option. This controls which KPP directory is used.
    set_dynamic_option(MECH 
        DEFAULT "${RUNDIR_MECH}"
        LOG GENERAL_OPTIONS_LOG
        SELECT_EXACTLY 1
        OPTIONS "Standard" "Tropchem" "SOA_SVPOA"
    )

    # Make LAYERS an option and set the appropriate definitions. Determine the 
    # default value based on RUNDIR_SIM.
    set(LAYERS_72_SIMS
        "standard"
        "benchmark"
        "aciduptake"
        "marinePOA"
        "TransportTracers"
        "custom"
        "HEMCO" # doesn't matter for the HEMCO standalone
    )
    set(LAYERS_47_SIMS
        "masscons"
        "POPs"
        "CH4"
        "tagCH4"
        "tagO3"
        "tagCO"
        "tagHg"
        "CO2"
        "aerosol"
        "Hg"
        "tropchem"
        "RRTMG"
        "complexSOA"
        "complexSOA_SVPOA"
        "TOMAS15"
        "TOMAS40"
    )
    if("${RUNDIR_SIM}" IN_LIST LAYERS_72_SIMS)
        set(LAYERS_DEFAULT "72")
    elseif("${RUNDIR_SIM}" IN_LIST LAYERS_47_SIMS)
        set(LAYERS_DEFAULT "47")
    else()
        message(FATAL_ERROR "Unknown simulation type \"${RUNDIR_SIM}\". Cannot determine LAYERS.")
    endif()
    set_dynamic_option(LAYERS 
        DEFAULT "${LAYERS_DEFAULT}"
        LOG GENERAL_OPTIONS_LOG
        SELECT_EXACTLY 1
        OPTIONS "47" "72"
    )
    if("${LAYERS}" STREQUAL "47")
        target_compile_definitions(BaseTarget INTERFACE GRIDREDUCED)
    endif()

    # Build with BPCH diagnostics?
    set_dynamic_option(BPCH 
        DEFAULT "DIAG" "TIMESER" "TPBC"
        OPTIONS "DIAG" "TIMESER" "TPBC"
        LOG GENERAL_OPTIONS_LOG
    )
    foreach(BPCH_DEFINE ${BPCH})
        target_compile_definitions(BaseTarget INTERFACE BPCH_${BPCH})
    endforeach()

    # Make an option for controlling the flexible precision. Set the appropriate
    # definition
    set_dynamic_option(PREC
        DEFAULT "REAL8"
        SELECT_EXACTLY 1
        OPTIONS "REAL4" "REAL8"
        LOG GENERAL_OPTIONS_LOG
    )
    if("${PREC}" STREQUAL "REAL8")
        target_compile_definitions(BaseTarget INTERFACE "USE_REAL8")
    endif()

    # Build with timers?
    if("${RUNDIR_SIM}" STREQUAL "benchmark")
        set(TIMERS_DEFAULT "TRUE")
    else()
        set(TIMERS_DEFAULT "FALSE")
    endif()
    set_dynamic_option(TIMERS 
        DEFAULT ${TIMERS_DEFAULT}
        LOG GENERAL_OPTIONS_LOG
        SELECT_EXACTLY 1
        OPTIONS "TRUE" "FALSE"
    )
    if(${TIMERS})
        target_compile_definitions(BaseTarget INTERFACE "USE_TIMERS")
    endif()

    gc_message(SECTION "General settings")
    dump_log(GENERAL_OPTIONS_LOG)

    # Build RRTMG?
    if("${RUNDIR_SIM}" STREQUAL "RRTMG")
        set(RRTMG_DEFAULT "TRUE")
    else()
        set(RRTMG_DEFAULT "FALSE")
    endif()
    set_dynamic_option(RRTMG 
        DEFAULT ${RRTMG_DEFAULT}
        LOG ADD_ONS_LOG
        SELECT_EXACTLY 1
        OPTIONS "TRUE" "FALSE"
    )
    if(${RRTMG})
        target_compile_definitions(BaseTarget INTERFACE "RRTMG")
    endif()

    # Build GTMM?
    set_dynamic_option(GTMM 
        DEFAULT "FALSE"
        LOG ADD_ONS_LOG
        SELECT_EXACTLY 1
        OPTIONS "TRUE" "FALSE"
    )
    if(${GTMM})
        target_compile_definitions(BaseTarget INTERFACE "GTMM_Hg")
    endif()

    # Build hemco_standalone?
    if("${RUNDIR_SIM}" STREQUAL "HEMCO")
        set(HCOSA_DEFAULT "TRUE")
    else()
        set(HCOSA_DEFAULT "FALSE")
    endif()
    set_dynamic_option(HCOSA 
        DEFAULT "${HCOSA_DEFAULT}"
        LOG ADD_ONS_LOG
        SELECT_EXACTLY 1
        OPTIONS "TRUE" "FALSE"
    )

    # Use the NC_HAS_COMPRESSION definition if nf_def_var_deflate is in netcdf.inc
    if(EXISTS ${NETCDF_F77_INCLUDE_DIR}/netcdf.inc)
        file(READ ${NETCDF_F77_INCLUDE_DIR}/netcdf.inc NCINC)
        if("${NCINC}" MATCHES ".*nf_def_var_deflate.*")
            target_compile_definitions(BaseTarget INTERFACE "NC_HAS_COMPRESSION")
        endif()
    endif()

    gc_message(SECTION "Other components")
    dump_log(ADD_ONS_LOG)

    # Determine which executables should be built
    set(GCCLASSIC_EXE_TARGETS "")
    if("${RUNDIR_SIM}" STREQUAL "HEMCO")
        list(APPEND GCCLASSIC_EXE_TARGETS "hemco_standalone")
    else()
        list(APPEND GCCLASSIC_EXE_TARGETS "geos")
    endif()
    if(GTMM)
        list(APPEND GCCLASSIC_EXE_TARGETS "gtmm")
    endif()

    # Export variables
    set(GCCLASSIC_EXE_TARGETS   ${GCCLASSIC_EXE_TARGETS}    PARENT_SCOPE)
    set(GCHP                    FALSE                       PARENT_SCOPE)
    set(MECH                    ${MECH}                     PARENT_SCOPE)
    set(TOMAS                   ${TOMAS}                    PARENT_SCOPE)
    set(RRTMG                   ${RRTMG}                    PARENT_SCOPE)
    set(GTMM                    ${GTMM}                     PARENT_SCOPE)
    set(RUNDIR                  ${RUNDIR}                   PARENT_SCOPE)
endfunction()
