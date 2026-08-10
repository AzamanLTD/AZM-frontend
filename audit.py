import os
import re

lib_dir = '/app/AZM-frontend/lib'

print("Scanning for Riverpod provider definitions precisely...")

dart_files = []
for root, dirs, files in os.walk(lib_dir):
    for file in files:
        if file.endswith('.dart'):
            dart_files.append(os.path.join(root, file))

# Regex to match provider declarations.
# E.g. final myProvider = Provider<...>(...) or final myProvider = Provider.family<...>(...)
# It captures:
# group 1: provider name
# group 2: provider type (e.g. FutureProvider, StateNotifierProvider, etc.)
# group 3: modifiers (e.g. .family, .autoDispose.family, .family.autoDispose)
# Let's search inside the content.
provider_decl_pattern = re.compile(
    r'\bfinal\s+(\w+)\s*=\s*((?:[A-Za-z0-9_]+\.)?(?:FutureProvider|StateNotifierProvider|Provider|ChangeNotifierProvider|StreamProvider|StateProvider|NotifierProvider))((?:\.[a-zA-Z0-9_]+)*)\s*(?:<[^>]+>)?\s*\(',
    re.MULTILINE
)

def find_matching_paren(text, start_idx):
    # Find matching parenthesis for the one starting at start_idx
    paren_count = 1
    i = start_idx
    while i < len(text):
        if text[i] == '(':
            paren_count += 1
        elif text[i] == ')':
            paren_count -= 1
            if paren_count == 0:
                return i
        i += 1
    return -1

# Let's test on all files
declarations = []
for df in dart_files:
    file_rel = os.path.relpath(df, lib_dir)
    with open(df, 'r', errors='ignore') as f:
        content = f.read()
    
    for match in provider_decl_pattern.finditer(content):
        prov_name = match.group(1)
        prov_type = match.group(2)
        prov_mods = match.group(3) or ''
        
        # Start of arguments inside the constructor
        start_idx = match.end()
        end_idx = find_matching_paren(content, start_idx)
        if end_idx == -1:
            continue
        
        args_text = content[start_idx-1 : end_idx+1]
        
        # Now let's find the closure/callback within the constructor arguments.
        # Usually, the callback is the first argument, like:
        # (ref) => ... or (ref, arg) => ... or (ref) { ... } or (ref, arg) { ... }
        # Or it might be `() => ...` or `(arg) => ...` (which is a bug!)
        # Let's find any lambda / function signature in the args_text.
        # We can look for the first occurrence of standard closure markers: `=>` or `{`
        # Let's find the first `=>` or `{` that is not inside another bracket/quote,
        # or use a regex to look for closures like `(...) =>` or `(...) {` at the top level of args_text.
        # Let's look for `\(([^)]*)\)\s*(?:async\s*)?(?:=>|\{)`
        closure_matches = re.finditer(r'\(([^)]*)\)\s*(?:async\s*)?(?:=>|\{)', args_text)
        
        # We want the first closure since that is typically the creation function for the provider.
        first_closure = None
        for cm in closure_matches:
            first_closure = cm
            break
            
        is_family = 'family' in prov_mods
        line_num = content[:match.start()].count('\n') + 1
        
        if first_closure:
            closure_args_raw = first_closure.group(1)
            closure_args = [a.strip() for a in closure_args_raw.split(',') if a.strip()]
            
            # Let's analyze closure_args
            # Issue: missing ref parameter.
            # 1. Any Provider.family that takes (someParam) instead of (ref, someParam)
            # 2. Any Provider that takes () instead of (ref)
            if is_family:
                if len(closure_args) < 2:
                    # Could be missing ref! E.g. (someParam) => or () =>
                    # Note: check if the first param is indeed 'ref'.
                    if len(closure_args) == 1 and closure_args[0] == 'ref':
                        # This means it takes only (ref), so it is missing the family parameter! But wait, is it?
                        # If a family provider only takes (ref), it is not a correct family provider definition.
                        declarations.append({
                            'file': file_rel,
                            'line': line_num,
                            'name': prov_name,
                            'type': prov_type + prov_mods,
                            'args': closure_args_raw,
                            'error': "Family provider has only 'ref' argument, missing family parameter"
                        })
                    elif len(closure_args) == 1:
                        # E.g. (someParam) => ... -> Missing 'ref'!
                        declarations.append({
                            'file': file_rel,
                            'line': line_num,
                            'name': prov_name,
                            'type': prov_type + prov_mods,
                            'args': closure_args_raw,
                            'error': "Family provider is missing 'ref' parameter"
                        })
                    elif len(closure_args) == 0:
                        declarations.append({
                            'file': file_rel,
                            'line': line_num,
                            'name': prov_name,
                            'type': prov_type + prov_mods,
                            'args': closure_args_raw,
                            'error': "Family provider has no arguments (should be (ref, param))"
                        })
                    elif closure_args[0] != 'ref':
                        declarations.append({
                            'file': file_rel,
                            'line': line_num,
                            'name': prov_name,
                            'type': prov_type + prov_mods,
                            'args': closure_args_raw,
                            'error': f"Family provider's first parameter is '{closure_args[0]}', should be 'ref'"
                        })
            else:
                # Non-family provider
                if len(closure_args) == 0:
                    declarations.append({
                        'file': file_rel,
                        'line': line_num,
                        'name': prov_name,
                        'type': prov_type + prov_mods,
                        'args': closure_args_raw,
                        'error': "Provider has no arguments (should take 'ref')"
                    })
                elif closure_args[0] != 'ref':
                    # Sometimes they use other names like `_` or `r`? Let's check, but typically it should be 'ref'.
                    if closure_args[0] not in ['ref', '_', 'r']:
                        declarations.append({
                            'file': file_rel,
                            'line': line_num,
                            'name': prov_name,
                            'type': prov_type + prov_mods,
                            'args': closure_args_raw,
                            'error': f"Provider's parameter is '{closure_args[0]}', should be 'ref'"
                        })
        else:
            # No closure found at all?
            # It might be defined like: final myProvider = Provider(myCreateFunction);
            # This is technically valid in Dart, but let's log it just in case.
            pass

print(f"Found {len(declarations)} potential provider definition issues:")
for d in declarations:
    print(f"File: {d['file']} | Line {d['line']} | Name: {d['name']} | Type: {d['type']} | Args: ({d['args']}) | Error: {d['error']}")
