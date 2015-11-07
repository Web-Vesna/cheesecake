# Cheesecake
Демон для управления сессиями.
## Список принимаемых запросов c ответами

* /session -- проверка факта авторизованности пользователя
  * Успех: `{ status: 'ok', uid: 100500, role: 'admin', name: 'name', lastname: 'lastname' }`
  * Фэйл: `{ status: 'error', message: 'unauthorized' }`
* /login -- открыть сессию
  * Успех: `{ status: 'ok', session_id: 'sdfhgjdhfasrewrjhgcxb' }`
  * Фэйл: `{ status: 'error', message: 'incorrect pass' }`
* /logout -- закрыть сессию
  * Успех: `{ status: 'ok' }`
  * Фэйл: `{ status: 'error', message: 'internal' }`
* /about -- получение информации о залогиненом пользователе
  * Успех: `{ status: 'ok', user_id: 100500, role: 'admin', name: 'name', lastname: 'lastname', login: 'login', email: 'e@mail.ru' }`
  * Фэйл: `{ status: 'error', message: 'unauthorized' }`

Все запросы принимают session_id и user_agent
Первый получается из куки (договорились, что шифровкой/дешифровкой будет заниматься сам чизкейк).

Авторизация дополнительно принимает параметры login && pass (session_id не принимается)
