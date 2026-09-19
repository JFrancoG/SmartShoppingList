#!/usr/bin/env python3
"""Validate the local API contract and its schema-ready JSON examples.

Requires Python 3.10+ and requirements-contract.txt, installed in a virtualenv.
Run from any directory; optional --contract/--examples paths support review copies.

Checks local JSON Pointer references, basic OpenAPI 3.2.1 structure, explicit
operation security, schema validity, operation coverage, and positive/negative
examples using JSON Schema 2020-12 and FormatChecker. This is not complete
OpenAPI meta-validation, HTTP serialization validation, or an API runtime test.
Only path/query parameters and application/json bodies are supported.
Example parameter values are already decoded and typed; bearer credentials are
described by security requirements rather than supplied in these examples.
"""

import argparse
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote

try:
    from jsonschema import Draft202012Validator, FormatChecker
    from jsonschema.exceptions import SchemaError
    from referencing import Registry, Resource
    from referencing.exceptions import Unresolvable
    from referencing.jsonschema import DRAFT202012
except ImportError:
    sys.exit("Install scripts/requirements-contract.txt in a virtualenv first.")


ROOT = Path(__file__).resolve().parents[1]
DOCUMENT_URI = "urn:smartshoppinglist:contract"
DIALECT_URI = "https://json-schema.org/draft/2020-12/schema"
METHODS = {"get", "put", "post", "delete", "options", "head", "patch", "trace", "query"}
MISSING = object()


class ContractError(Exception):
    """The document or example harness is malformed or unsupported."""


def require(condition, message):
    if not condition:
        raise ContractError(message)


def pointer(parent, key):
    return parent + "/" + str(key).replace("~", "~0").replace("/", "~1")


def walk(value, location=""):
    yield location, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from walk(child, pointer(location, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, pointer(location, index))


def load_json(path):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"{path}: duplicate JSON key {key!r}")
            result[key] = value
        return result

    def reject_constant(value):
        raise ContractError(f"{path}: non-JSON numeric constant {value}")

    with path.open(encoding="utf-8") as source:
        return json.load(source, object_pairs_hook=unique_object, parse_constant=reject_constant)


class Contract:
    def __init__(self, document):
        self.document = document
        self.operations = {}
        self.checked_schemas = set()
        self.formats = FormatChecker()
        self.registry = Registry().with_resource(
            DOCUMENT_URI, Resource(contents=document, specification=DRAFT202012)
        )
        self.inspect()

    def at(self, reference):
        require(isinstance(reference, str) and reference.startswith("#"),
                f"Only local JSON Pointer $refs are supported: {reference!r}")
        fragment = unquote(reference[1:])
        require(not fragment or fragment.startswith("/"), f"Unsupported $ref: {reference}")
        value = self.document
        for token in fragment.split("/")[1:]:
            require(re.search(r"~(?![01])", token) is None, f"Invalid JSON Pointer: {reference}")
            token = token.replace("~1", "/").replace("~0", "~")
            if isinstance(value, list):
                require(re.fullmatch(r"0|[1-9][0-9]*", token) is not None,
                        f"Invalid array index in $ref: {reference}")
                index = int(token)
                require(index < len(value), f"Unresolved $ref: {reference}")
                value = value[index]
            else:
                require(isinstance(value, dict) and token in value, f"Unresolved $ref: {reference}")
                value = value[token]
        return value, fragment

    def object_at(self, location):
        value, location = self.at("#" + location)
        visited = set()
        while isinstance(value, dict) and "$ref" in value:
            require(location not in visited, f"Cyclic OpenAPI object reference at #{location}")
            require(set(value) <= {"$ref", "summary", "description"},
                    f"Unsupported OpenAPI reference siblings at #{location}")
            visited.add(location)
            value, location = self.at(value["$ref"])
        require(isinstance(value, dict), f"Expected object at #{location}")
        return value, location

    def check_schema(self, location):
        if location in self.checked_schemas:
            return
        schema, _ = self.at("#" + location)
        try:
            Draft202012Validator.check_schema(schema)
        except SchemaError as error:
            raise ContractError(f"Invalid JSON Schema at #{location}: {error.message}") from error
        self.checked_schemas.add(location)
        if isinstance(schema, bool):
            return
        if "format" in schema:
            require(schema["format"] in self.formats.checkers,
                    f"Unknown or unavailable JSON Schema format {schema['format']!r} at #{location}")
        if "$ref" in schema:
            _, target = self.at(schema["$ref"])
            self.check_schema(target)
        # Visit schema positions only. const/default/enum/examples contain data,
        # and property names such as 'format' are not themselves schema keywords.
        for keyword in ("properties", "patternProperties", "$defs", "dependentSchemas"):
            for name in schema.get(keyword, {}):
                self.check_schema(pointer(pointer(location, keyword), name))
        for keyword in ("allOf", "anyOf", "oneOf", "prefixItems"):
            for index in range(len(schema.get(keyword, []))):
                self.check_schema(pointer(pointer(location, keyword), index))
        for keyword in ("additionalProperties", "unevaluatedProperties", "propertyNames",
                        "items", "contains", "unevaluatedItems", "not", "if", "then",
                        "else", "contentSchema"):
            if keyword in schema:
                self.check_schema(pointer(location, keyword))

    def json_body_schema(self, value, location):
        content = value.get("content", {})
        require(isinstance(content, dict), f"Invalid content at #{location}")
        if not content:
            return None
        require(set(content) == {"application/json"},
                f"Only application/json content is supported at #{location}")
        media, media_location = self.object_at(pointer(pointer(location, "content"), "application/json"))
        require("schema" in media, f"Missing JSON body schema at #{media_location}")
        schema_location = pointer(media_location, "schema")
        self.check_schema(schema_location)
        return schema_location

    def parameters(self, path_item, path_location, operation, operation_location):
        combined = {}
        for owner, location in ((path_item, path_location), (operation, operation_location)):
            entries = owner.get("parameters", [])
            require(isinstance(entries, list), f"Invalid parameters at #{location}")
            local_keys = set()
            for index in range(len(entries)):
                value, parameter_location = self.object_at(pointer(pointer(location, "parameters"), index))
                name, destination = value.get("name"), value.get("in")
                require(isinstance(name, str) and name, f"Unnamed parameter at #{parameter_location}")
                require(destination in {"path", "query"},
                        f"Unsupported parameter location at #{parameter_location}: {destination!r}")
                require("schema" in value and "content" not in value,
                        f"Parameter must use schema at #{parameter_location}")
                require(isinstance(value.get("required", False), bool),
                        f"Invalid required flag at #{parameter_location}")
                require(destination != "path" or value.get("required") is True,
                        f"Path parameter must be required at #{parameter_location}")
                key = (destination, name)
                require(key not in local_keys, f"Duplicate parameter {key} at #{location}")
                local_keys.add(key)
                schema_location = pointer(parameter_location, "schema")
                self.check_schema(schema_location)
                combined[key] = (value, schema_location)
        return combined

    def inspect(self):
        doc = self.document
        require(isinstance(doc, dict), "Contract must be a JSON object")
        require(doc.get("openapi") == "3.2.1", "Expected openapi: 3.2.1")
        require(doc.get("jsonSchemaDialect", DIALECT_URI) == DIALECT_URI,
                "This validator requires JSON Schema draft 2020-12")
        info = doc.get("info", {})
        require(isinstance(info, dict) and all(isinstance(info.get(k), str) and info[k]
                for k in ("title", "version")), "Contract needs info.title and info.version")
        for location, value in walk(doc):
            if isinstance(value, dict) and "$ref" in value:
                self.at(value["$ref"])
            if isinstance(value, dict):
                require(value.get("$schema", DIALECT_URI) == DIALECT_URI,
                        f"Unsupported JSON Schema dialect at #{location}")
                require(not ({"$id", "$anchor", "$dynamicAnchor", "$dynamicRef"} & value.keys()),
                        f"Only document-relative JSON Pointer schemas are supported at #{location}")
        components = doc.get("components", {})
        require(isinstance(components, dict), "components must be an object")
        schemas = components.get("schemas", {})
        require(isinstance(schemas, dict), "components.schemas must be an object")
        for name in schemas:
            self.check_schema(pointer("/components/schemas", name))
        security_schemes = components.get("securitySchemes", {})
        require(isinstance(security_schemes, dict), "securitySchemes must be an object")
        paths = doc.get("paths")
        require(isinstance(paths, dict) and paths, "Contract needs nonempty paths")
        require(not doc.get("webhooks"), "Webhook validation is outside this contract validator")
        for path in paths:
            if path.startswith("x-"):
                continue
            require(path.startswith("/"), f"Invalid path: {path}")
            path_item, path_location = self.object_at(pointer("/paths", path))
            require(not path_item.get("additionalOperations"), "Additional HTTP methods are unsupported")
            for method in sorted(METHODS & path_item.keys()):
                operation_location = pointer(path_location, method)
                operation, operation_location = self.object_at(operation_location)
                identifier = operation.get("operationId")
                require(isinstance(identifier, str) and identifier, f"Missing operationId: {method} {path}")
                require(identifier not in self.operations, f"Duplicate operationId: {identifier}")
                require(not operation.get("callbacks"), f"Callbacks are unsupported: {identifier}")
                require("security" in operation and isinstance(operation["security"], list),
                        f"Explicit security is required on {identifier}; use [] for public operations")
                for requirement in operation["security"]:
                    require(isinstance(requirement, dict), f"Invalid security requirement: {identifier}")
                    for name, scopes in requirement.items():
                        require(name in security_schemes, f"Unknown security scheme {name}: {identifier}")
                        require(isinstance(scopes, list) and all(isinstance(s, str) for s in scopes),
                                f"Invalid security scopes: {identifier}")
                parameters = self.parameters(path_item, path_location, operation, operation_location)
                placeholders = set(re.findall(r"\{([^{}]+)\}", path))
                declared = {name for destination, name in parameters if destination == "path"}
                require(placeholders == declared, f"Path placeholders and parameters differ: {identifier}")
                body_schema, body_required = None, False
                if "requestBody" in operation:
                    body, body_location = self.object_at(pointer(operation_location, "requestBody"))
                    body_schema = self.json_body_schema(body, body_location)
                    require(body_schema is not None, f"Missing request content: {identifier}")
                    body_required = body.get("required", False)
                    require(isinstance(body_required, bool), f"Invalid requestBody.required: {identifier}")
                responses = operation.get("responses")
                require(isinstance(responses, dict) and responses, f"Missing responses: {identifier}")
                response_schemas = {}
                for status in responses:
                    if status.startswith("x-"):
                        continue
                    require(status == "default" or re.fullmatch(r"[1-5](?:[0-9]{2}|XX)", status),
                            f"Invalid response status {status}: {identifier}")
                    response, response_location = self.object_at(pointer(pointer(operation_location, "responses"), status))
                    require(isinstance(response.get("description"), str),
                            f"Response needs description: {identifier}/{status}")
                    response_schemas[status] = self.json_body_schema(response, response_location)
                require(response_schemas, f"No HTTP responses: {identifier}")
                self.operations[identifier] = (parameters, body_schema, body_required, response_schemas)
        require(self.operations, "No operations found")

    def schema_errors(self, value, location, label):
        validator = Draft202012Validator(
            {"$ref": DOCUMENT_URI + "#" + location},
            registry=self.registry, format_checker=self.formats,
        )
        return [f"{label}{error.json_path}: {error.message}" for error in validator.iter_errors(value)]

    def request_errors(self, request, operation):
        require(isinstance(request, dict), "Example request must be an object")
        require(set(request) <= {"path", "query", "body"}, "Unknown example request fields")
        parameters, body_schema, body_required, _ = operation
        errors = []
        for destination, field in (("path", "path"), ("query", "query")):
            values = request.get(field, {})
            require(isinstance(values, dict), f"Example request.{field} must be an object")
            declared = {name for place, name in parameters if place == destination}
            errors.extend(f"request.{field}: undeclared parameter {name}" for name in sorted(values.keys() - declared))
            for name in sorted(declared):
                definition, schema_location = parameters[(destination, name)]
                if name in values:
                    errors.extend(self.schema_errors(values[name], schema_location, f"request.{field}.{name}"))
                elif definition.get("required", False):
                    errors.append(f"request.{field}: missing required parameter {name}")
        if "body" in request:
            if body_schema is None:
                errors.append("request.body: operation declares no request body")
            else:
                errors.extend(self.schema_errors(request["body"], body_schema, "request.body"))
        elif body_required:
            errors.append("request.body: required body is missing")
        return errors

    def response_errors(self, response, operation):
        require(isinstance(response, dict) and set(response) <= {"status", "body"},
                "Example response must contain only status and optional body")
        status = response.get("status")
        require(type(status) is int and 100 <= status <= 599, "Example response.status must be an HTTP integer")
        responses = operation[3]
        schema = responses.get(str(status), responses.get(f"{status // 100}XX", responses.get("default", MISSING)))
        if schema is MISSING:
            return [f"response.status: undeclared status {status}"]
        if schema is None:
            return ["response.body: response declares no content"] if "body" in response else []
        if "body" not in response:
            return ["response.body: declared JSON body is missing"]
        return self.schema_errors(response["body"], schema, "response.body")


def validate_examples(contract, examples):
    require(isinstance(examples, dict), "Examples must be a JSON object")
    require(set(examples) == {"contractVersion", "cases", "invalidRequests"}, "Unexpected examples structure")
    require(examples["contractVersion"] == contract.document["info"]["version"], "Example contractVersion differs from info.version")
    require(isinstance(examples["cases"], list) and examples["cases"], "cases must be a nonempty array")
    require(isinstance(examples["invalidRequests"], list), "invalidRequests must be an array")
    failures, identifiers, coverage = [], set(), set()
    for group in ("cases", "invalidRequests"):
        for case in examples[group]:
            require(isinstance(case, dict), f"{group} entries must be objects")
            required = {"id", "operationId", "request"} | ({"response"} if group == "cases" else set())
            require(set(case) == required, f"Unexpected fields in {group} entry: {case.get('id')}")
            identifier = case["id"]
            require(isinstance(identifier, str) and identifier and identifier not in identifiers,
                    f"Missing or duplicate example id: {identifier!r}")
            identifiers.add(identifier)
            operation_id = case["operationId"]
            require(isinstance(operation_id, str) and operation_id in contract.operations,
                    f"Unknown operationId in {identifier}: {operation_id!r}")
            operation = contract.operations[operation_id]
            errors = contract.request_errors(case["request"], operation)
            if group == "invalidRequests":
                if not errors:
                    failures.append(f"{identifier}: negative request unexpectedly satisfies the contract")
            else:
                coverage.add(operation_id)
                errors.extend(contract.response_errors(case["response"], operation))
                failures.extend(f"{identifier}: {error}" for error in errors)
    failures.extend(f"No positive example for operation: {name}" for name in sorted(contract.operations.keys() - coverage))
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=ROOT / "docs/contracts/openapi.json")
    parser.add_argument("--examples", type=Path, default=ROOT / "docs/contracts/examples.json")
    args = parser.parse_args()
    try:
        contract = Contract(load_json(args.contract))
        examples = load_json(args.examples)
        failures = validate_examples(contract, examples)
    except (ContractError, OSError, ValueError, RecursionError, Unresolvable) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(f"PASS: {len(contract.operations)} operations, {len(examples['cases'])} positive examples, "
          f"{len(examples['invalidRequests'])} negative requests; JSON Schema 2020-12 formats checked.")
    print("Scope: structural contract and examples; not complete OpenAPI meta-validation or API runtime tests.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
