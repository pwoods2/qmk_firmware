function(validate_json JSON_FILE SCHEMA_NAME JSON_STRING_STR)
  unset(${JSON_STRING_STR} PARENT_SCOPE)
  message(STATUS "Validating ${JSON_FILE} with '${SCHEMA_NAME}' schema")
  file(READ ${JSON_FILE} JSON_STRING)
  file(READ ${CMAKE_SOURCE_DIR}/data/schemas/${SCHEMA_NAME}.jsonschema SCHEMA_STRING)
  string(JSON SCHEMA_ID GET ${SCHEMA_STRING} $id)

  set(DEFINITIONS "{}")
  file(READ ${CMAKE_SOURCE_DIR}/data/schemas/definitions.jsonschema DEFINITIONS_STRING)
  string(JSON DEFINITION_ID GET ${DEFINITIONS_STRING} $id)
  string(JSON DEFINITIONS SET ${DEFINITIONS} "${DEFINITION_ID}#" ${DEFINITIONS_STRING})

  string(JSON SCHEMA_DEFINITIONS ERROR_VARIABLE JSON_ERROR GET ${SCHEMA_STRING} definitions)
  if(${JSON_ERROR} STREQUAL "NOTFOUND")
    string(JSON DEFINITIONS SET ${DEFINITIONS} "#" "{}")
    string(JSON DEFINITIONS SET ${DEFINITIONS} "#" definitions ${SCHEMA_DEFINITIONS})
    # string(JSON DEFINITIONS_LENGTH LENGTH ${SCHEMA_DEFINITIONS})
    # math(EXPR MAX "${DEFINITIONS_LENGTH} - 1")
    # foreach(IDX RANGE ${MAX})
    #   string(JSON DEFINITION_NAME MEMBER ${SCHEMA_DEFINITIONS} ${IDX})
    #   string(JSON DEFINITION GET ${SCHEMA_DEFINITIONS} ${DEFINITION_NAME})
    #   message(DEBUG "Loading local definition '${DEFINITION_NAME}'")
    #   string(JSON DEFINITIONS_STRING SET ${DEFINITIONS_STRING} ${DEFINITION_NAME} ${DEFINITION})
    # endforeach()
  endif()
  
  validate_object(${JSON_STRING} ${SCHEMA_STRING} OBJECT_ERROR)
  if(DEFINED OBJECT_ERROR)
    message(FATAL_ERROR ${OBJECT_ERROR})
  else()
    set(${JSON_STRING_STR} ${JSON_STRING} PARENT_SCOPE)
  endif()
endfunction()

function(validate_object JSON_STRING SCHEMA_STRING OBJECT_ERROR_STR)
  unset(${OBJECT_ERROR_STR} PARENT_SCOPE)
  set(OBJECT_ERROR)
  string(JSON PROPERTY_NAME_SCHEMA ERROR_VARIABLE PROPERTY_NAMES_ERROR GET ${SCHEMA_STRING} propertyNames)
  string(JSON REQUIRED_PROPERTIES ERROR_VARIABLE REQUIRED_PROPERTIES_ERROR GET ${SCHEMA_STRING} required)
  set(REQUIRED_LIST)
  if(${REQUIRED_PROPERTIES_ERROR} STREQUAL "NOTFOUND")
    string(JSON REQUIRED_LENGTH LENGTH ${REQUIRED_PROPERTIES})
    math(EXPR MAX "${REQUIRED_LENGTH} - 1")
    foreach(IDX RANGE ${MAX})
      string(JSON REQUIRED GET ${REQUIRED_PROPERTIES} ${IDX})
      list(APPEND REQUIRED_LIST ${REQUIRED})
    endforeach()
  endif()
  string(JSON NUM_PROPERTIES LENGTH ${JSON_STRING})
  math(EXPR MAX "${NUM_PROPERTIES} - 1")
  foreach(IDX RANGE ${MAX})
    string(JSON PROPERTY_NAME MEMBER ${JSON_STRING} ${IDX})
    list(REMOVE_ITEM REQUIRED_LIST ${PROPERTY_NAME})
    message(DEBUG "Validating property '${PROPERTY_NAME}'")
    if(${PROPERTY_NAMES_ERROR} STREQUAL "NOTFOUND")
      validate_property(${PROPERTY_NAME} ${PROPERTY_NAME_SCHEMA} PROPERTY_NAME_ERROR)
      if(DEFINED PROPERTY_NAME_ERROR)
        list(APPEND OBJECT_ERROR "${PROPERTY_NAME_ERROR}")
      endif()
    endif()
    string(JSON PROPERTY GET ${JSON_STRING} ${PROPERTY_NAME})
    string(JSON SCHEMA_PROPERTIES ERROR_VARIABLE PROPERTIES_ERROR GET ${SCHEMA_STRING} properties ${PROPERTY_NAME})
    if(${PROPERTIES_ERROR} STREQUAL "NOTFOUND")
      string(JSON PROPERTY_SCHEMA GET ${SCHEMA_STRING} properties ${PROPERTY_NAME})
    else()
      string(JSON PROPERTY_SCHEMA ERROR_VARIABLE ADDITIONAL_PROPERTIES_ERROR GET ${SCHEMA_STRING} additionalProperties)
      if(NOT ${ADDITIONAL_PROPERTIES_ERROR} STREQUAL "NOTFOUND" OR "${PROPERTY_SCHEMA}" STREQUAL "OFF")
        list(APPEND OBJECT_ERROR "Additional properties like '${PROPERTY_NAME}' not permitted in '${JSON_STRING}'")
      endif()
    endif()
    validate_property(${PROPERTY} ${PROPERTY_SCHEMA} PROPERTY_ERROR)
    if(DEFINED PROPERTY_ERROR)
      list(APPEND OBJECT_ERROR "${PROPERTY_ERROR}")
    endif()
  endforeach()
  list(LENGTH REQUIRED_LIST REQUIRED_REMAINING_LENGTH)
  if(${REQUIRED_REMAINING_LENGTH} GREATER 0)
    list(APPEND OBJECT_ERROR "Required properties not found: ${REQUIRED_LIST}")
  endif()
  set(${OBJECT_ERROR_STR} ${OBJECT_ERROR} PARENT_SCOPE)
endfunction()

function(validate_property PROPERTY PROPERTY_SCHEMA PROPERTY_ERROR_STR)
  unset(${PROPERTY_ERROR_STR} PARENT_SCOPE)
  set(PROPERTY_ERROR)
  string(JSON PROPERTY_REF ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} $ref)
  if(${JSON_ERROR} STREQUAL "NOTFOUND")
    string(REPLACE "/" ";" REF_COMPONENTS "${PROPERTY_REF}")
    string(JSON PROPERTY_SCHEMA GET ${DEFINITIONS} ${REF_COMPONENTS})
  endif()
  string(JSON PROPERTY_TYPE ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} type)
  if(${JSON_ERROR} STREQUAL "NOTFOUND")
    message(DEBUG "Validating property type '${PROPERTY_TYPE}'")
    if(${PROPERTY_TYPE} STREQUAL "object")
      validate_object(${PROPERTY} ${PROPERTY_SCHEMA} OBJECT_ERROR)
      if(DEFINED OBJECT_ERROR)
        list(APPEND PROPERTY_ERROR ${OBJECT_ERROR})
      endif()
    elseif(${PROPERTY_TYPE} STREQUAL "array")
      string(JSON ARRAY_LENGTH LENGTH ${PROPERTY})
      string(JSON MAX_ITEMS ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} maxItems)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND ${ARRAY_LENGTH} GREATER ${MAX_ITEMS})
        list(APPEND PROPERTY_ERROR "Number of items in '${PROPERTY}' exceeds maximum ${MAX_ITEMS}")
      endif()
      string(JSON MIN_ITEMS ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} minItems)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND ${ARRAY_LENGTH} LESS ${MIN_ITEMS})
        list(APPEND PROPERTY_ERROR "Number of items in '${PROPERTY}' is less than ${MIN_ITEMS}")
      endif()
      string(JSON ITEM_SCHEMA ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} items)
      if(${JSON_ERROR} STREQUAL "NOTFOUND")
        math(EXPR MAX "${ARRAY_LENGTH} - 1")
        foreach(IDX RANGE ${MAX})
          string(JSON ITEM GET ${PROPERTY} ${IDX})
          validate_property(${ITEM} ${ITEM_SCHEMA} ITEM_ERROR)
          if(DEFINED ITEM_ERROR)
            list(APPEND PROPERTY_ERROR ${ITEM_ERROR})
          endif()
        endforeach()
      endif()
    elseif(${PROPERTY_TYPE} STREQUAL "null")
      if(NOT "${PROPERTY}" STREQUAL "null")
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is not null'")
      endif()
    elseif(${PROPERTY_TYPE} STREQUAL "boolean")
      if(NOT "${PROPERTY}" STREQUAL "OFF" AND NOT "${PROPERTY}" STREQUAL "ON")
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is not a boolean'")
      endif()
    elseif(${PROPERTY_TYPE} STREQUAL "number")
      if(NOT "${PROPERTY}" MATCHES "-?[0-9]+\\.?[0-9]*")
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is not a number'")
      endif()
    elseif(${PROPERTY_TYPE} STREQUAL "integer")
      if(NOT "${PROPERTY}" MATCHES "-?[0-9]+")
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is not an integer'")
      endif()
      string(JSON MIN ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} minimum)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND ${PROPERTY} LESS ${MIN})
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is less than the minimum of ${MIN}")
      endif()
      string(JSON MAX ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} maximum)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND ${PROPERTY} GREATER ${MAX})
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is greater than the maximum of ${MAX}")
      endif()
    elseif(${PROPERTY_TYPE} STREQUAL "string")
      # cmake regex doesn't support {}, so other options might be needed here
      string(JSON PATTERN ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} pattern)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND NOT "${PROPERTY}" MATCHES "${PATTERN}")
        list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' does not match '${PATTERN}'")
      endif()
      string(LENGTH ${PROPERTY} STRING_LENGTH)
      string(JSON MIN_LENGTH ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} minLength)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND ${STRING_LENGTH} LESS ${MIN_LENGTH})
        list(APPEND PROPERTY_ERROR "Length of property '${PROPERTY}' is less than the minimum of ${MIN_LENGTH}")
      endif()
      string(JSON MAX_LENGTH ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} maxLength)
      if(${JSON_ERROR} STREQUAL "NOTFOUND" AND ${STRING_LENGTH} GREATER ${MAX_LENGTH})
        list(APPEND PROPERTY_ERROR "Length of property '${PROPERTY}' is greater than the maximum of ${MAX_LENGTH}")
      endif()
      string(JSON ENUM_LIST ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} enum)
      if(${JSON_ERROR} STREQUAL "NOTFOUND")
        set(FOUND_IN_ENUM_LIST FALSE)
        string(JSON ENUM_LENGTH LENGTH ${ENUM_LIST})
        math(EXPR MAX "${ENUM_LENGTH} - 1")
        foreach(IDX RANGE ${MAX})
          string(JSON ENUM GET ${PROPERTY_SCHEMA} enum ${IDX})
          if(${ENUM} STREQUAL ${PROPERTY})
            set(FOUND_IN_ENUM_LIST TRUE)
          endif()
        endforeach()
        if(NOT ${FOUND_IN_ENUM_LIST})
          list(APPEND PROPERTY_ERROR "Property '${PROPERTY}' is not defined in the schema's enum: ${ENUM_LIST}")
        endif()
      endif()
    else()
      message(STATUS "Unknown type '${PROPERTY_TYPE}'")
    endif()
  else()
    string(JSON PROPERTY_ONEOF ERROR_VARIABLE JSON_ERROR GET ${PROPERTY_SCHEMA} oneOf)
    if(${JSON_ERROR} STREQUAL "NOTFOUND")
      set(TYPE_SUCCESS FALSE)
      string(JSON NUM_ONEOF LENGTH ${PROPERTY_ONEOF})
      math(EXPR MAX "${NUM_ONEOF} - 1")
      set(ONEOF_ERRORS)
      foreach(IDX RANGE ${MAX})
        string(JSON PROPERTY_SCHEMA GET ${PROPERTY_ONEOF} ${IDX})
        validate_property(${PROPERTY} ${PROPERTY_SCHEMA} ONEOF_ERROR)
        if(NOT DEFINED ONEOF_ERROR)
          set(TYPE_SUCCESS TRUE)
        else()
          list(APPEND ONEOF_ERRORS "${ONEOF_ERROR}\n")
        endif()
      endforeach()
      if(NOT TYPE_SUCCESS)
        list(APPEND PROPERTY_ERROR "Could not validate oneOf type '${PROPERTY}' :\n${ONEOF_ERRORS}")
      endif()
    endif()
  endif()
  set(${PROPERTY_ERROR_STR} ${PROPERTY_ERROR} PARENT_SCOPE)
endfunction()