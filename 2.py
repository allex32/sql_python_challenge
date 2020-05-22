input_list = [[1,2],[5,4,1],[8,9,4],[15,16],[20]]
adj_dict = {}
not_visited = set()
visited = set()

#Наполнение списка смежности графа
for el in input_list:
    for (index, v) in enumerate(el):
       not_visited.add(v)
       if v not in adj_dict:
           adj_dict[v] = set()
       adj_dict[v].update(el[:(index)] + el[(index+1):])

print(adj_dict)

#Функция обхода графа в глубину
def dfs(v):
    visited.add(v)
    not_visited.remove(v)
    for w in adj_dict[v]:
        if w in not_visited:
            dfs(w)

#Нахождение компонент связности графа
while not_visited:
    visited = set()
    dfs(next(iter(not_visited)))
    print(visited)
