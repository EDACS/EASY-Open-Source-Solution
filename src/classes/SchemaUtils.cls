/**
 * Created by maxim_elets on 10/23/19.
 */

public with sharing class SchemaUtils {

	/**
	* @description Get all fields of a SObject.
	* @param p_sobjectType Schema.SObjectType of a SObject tgetAllFieldso get writable fields.
	* @return List of Schema.SObjectField writable fields.
	*/
	public static List<Schema.SObjectField> getAllFields(Schema.SObjectType p_sobjectType, Set<String> p_filedsToIgnore) {

		List<Schema.SObjectField> writableFields = new List<Schema.SObjectField>();
		List<Schema.SObjectField> allSobjectFields = p_sobjectType.getDescribe().fields.getMap().values();

		for(Schema.SObjectField field : allSobjectFields) {
			if ( p_filedsToIgnore == NULL || ! p_filedsToIgnore.contains(field.getDescribe().getName())) {
				writableFields.add(field);
			}
		}
		return writableFields;
	}
}