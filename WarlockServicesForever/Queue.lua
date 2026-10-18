WSFQueue = {}

function WSFQueue.New()
    return { names = {}, lookup = {} }
end

function WSFQueue.Add(queue, name, message)
    if type(name) ~= "string" or not string.find(name, "%S") then return false end
    if type(message) ~= "string" or not string.match(message, "^%s*123%s*$") then return false end
    local key = string.lower(name)
    if queue.lookup[key] then return false end
    queue.lookup[key] = true
    table.insert(queue.names, name)
    return true
end

function WSFQueue.Remove(queue, index)
    local name = queue.names[index]
    if not name then return end
    queue.lookup[string.lower(name)] = nil
    table.remove(queue.names, index)
    return name
end
