package org.xtendroid.json

/**
 * Created by jasmsison on 02/02/16.
 */

import org.eclipse.xtend.lib.macro.AbstractClassProcessor
import org.eclipse.xtend.lib.macro.Active
import org.eclipse.xtend.lib.macro.RegisterGlobalsContext
import org.eclipse.xtend.lib.macro.TransformationContext
import org.eclipse.xtend.lib.macro.declaration.ClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.Visibility

import org.json.JSONObject

// for some reason I can't import from a different package within the same -ing module
//import static extension de.itemis.jsonized.JsonObjectEntry.*
import static extension org.xtendroid.json.JsonObjectEntry.*
import org.json.JSONException

/**
 * Structure by example.
 *
 * You have a JSON snippet - I build your classes.
 */
@Active(AndroidJsonizedProcessor)
annotation AndroidJsonized {
    /**
     * value could be a url or a valid json object, e.g. '{"a" : "string", "b" : true, "c" : 48}'
     */
    String value
}

class AndroidJsonizedProcessor extends AbstractClassProcessor {

    /**
     * Called first. Only register any new types you want to generate here.
     */
    override doRegisterGlobals(ClassDeclaration clazz, RegisterGlobalsContext context) {
        // visit the whole JSON tree and register any nested classes
        registerClassNamesRecursively(clazz.jsonEntries, context)
    }

    private def void registerClassNamesRecursively(Iterable<JsonObjectEntry> json, RegisterGlobalsContext context) {
        for (jsonEntry : json) {
            if (jsonEntry.isJsonObject) {
                context.registerClass(jsonEntry.className)
                registerClassNamesRecursively(jsonEntry.childEntries, context)
            }
        }
    }

    /**
     * Called secondly. Modify the types.
     */
    override doTransform(MutableClassDeclaration clazz, extension TransformationContext context) {
        clazz.addWarning("className: " + clazz.simpleName)
        enhanceClassesRecursively(clazz, clazz.jsonEntries, context)
        clazz.addConstructor [
            addParameter('jsonObject', JSONObject.newTypeReference)
            body = '''
                mJsonObject = jsonObject;
            '''
        ]
    }

    def void enhanceClassesRecursively(MutableClassDeclaration clazz, Iterable<? extends JsonObjectEntry> entries, extension TransformationContext context) {

        clazz.addField("mDirty") [
            type = typeof(boolean).newTypeReference
            visibility = Visibility.PRIVATE
        ]

        // do not add fields, directly modify the json object
        clazz.addField("mJsonObject") [
            type = JSONObject.newTypeReference
            visibility = Visibility.PRIVATE
        ]

        clazz.addMethod("toJSONObject") [
            returnType = JSONObject.newTypeReference
            body = '''
                return mJsonObject;
            '''
        ]

        // TODO deterimine the (generated) difference between this and typeof(boolean).newTypeReference
        clazz.addMethod("isDirty") [
            returnType = Boolean.newTypeReference
            body = '''
                return mDirty;
            '''
        ]

/*
        // TODO remove
        val string = clazz.annotations.head.getValue('value').toString
        clazz.addWarning(String.format('value = %s', string))
*/

        // add accessors for the entries
        for (entry : entries) {
            val basicType = entry.getComponentType(context)
            val realType = if(entry.isArray) getList(basicType) else basicType
            val memberName = basicType.simpleName.toFirstLower

            // TODO remove
            clazz.addWarning(String.format('property = %s, basicType = %s, realType = %s, entry.isJsonObject = %b', entry.propertyName, basicType.simpleName, realType.simpleName, entry.isJsonObject))

            // add JSONObject container for lazy-getting
            // TODO determine if this also works for aggregate types
            if (entry.isJsonObject || entry.isArray)
            {
                clazz.addField(realType.simpleName.toFirstLower) [
                    type = realType
                    visibility = Visibility.PROTECTED
                    // make it possible to extend, e.g. BigInteger, BigNumber
                    // TODO add an option to annotation to mark fields as special fields
                    // generate Date converters, BigInteger/BigNumber etc.
                    // @AndroidJsonizer(value = "http://...", mapping = # { 'anInteger' -> BigInteger, 'aFloat' -> BigNumber, 'timestamp' -> Date })
                    // @AndroidJsonizer(value = '{ "anInteger" : 1234, "aFloat" : 12.34 }', mapping = # { 'anInteger' -> BigInteger, 'aFloat' -> BigNumber, 'timestamp' -> Date })
                ]
            }

            clazz.addMethod("get" + entry.key.toFirstUpper) [
                returnType = realType
                exceptions = JSONException.newTypeReference
                // TODO primitive aggregate and non-primitive aggregate
                if (entry.isArray)
                {
                    body = ['''
                        // TODO array implementation, primitive and non-primitive (i.e. JSONObject)
                    ''']
                }else if (entry.isJsonObject)
                {
                    body = ['''
                        if («memberName» == null) {
                            «memberName» = new «basicType.simpleName»(mJsonObject.getJSONObject("«entry.key»"));
                        }
                        return «memberName»;
				    ''']
                }else {
                    body = ['''
                        return mJsonObject.get«basicType.simpleName.toFirstUpper»("«entry.key»");
                    ''']
                }
            ]

            // chainable
            // TODO primitive aggregate and non-primitive aggregate
            // TODO set composite type (i.e. JSONObject) in the JSONObject,
            // TODO this requires a toJSONString method
            clazz.addMethod("set" + entry.key.toFirstUpper) [
                addParameter(entry.key, realType)
                returnType = clazz.newTypeReference
                exceptions = JSONException.newTypeReference
                if (entry.isArray)
                {
                    body = ['''
                        // TODO array implementation, primitive and non-primitive (i.e. JSONObject)
                    ''']
                }else if (entry.isJsonObject) // TODO determine if this is applicable for arrays
                {
                    body = ['''
                        mDirty = true;
                        mJsonObject.put("«entry.key»", «entry.key».toJSONObject());
                        return this;
				    ''']
                }else {
                    body = ['''
                        mDirty = true;
                        mJsonObject.put("«entry.key»", «entry.key»);
                        return this;
                    ''']
                }
            ]

            // TODO determine array types are correct
            // if it's a JSON Object call enhanceClass recursively
            // TODO for some reason this is fuxxored, this only applies
            // to org.json.JSONObject and org.json.JSONArray
            if (entry.isJsonObject)
                enhanceClassesRecursively(findClass(entry.className), entry.childEntries, context)
        }
    }
}
