#include <stdio.h>
#include <stdint.h>
#include <wchar.h>

#define MUL 1000000.0

class MONEY
{
public:
	MONEY(double d) {
		m_data[0] = (int64_t)(d * MUL);
		m_data[1] = 0;
	}
	double ToDouble() const {
		return m_data[0] / MUL;
	}
private:
	int64_t m_data[2];
	friend void AddMoney(MONEY *money, double d);
};

void AddMoney(MONEY *money, double d)
{
	money->m_data[0] += (int64_t)(d * MUL);
	money->m_data[1] += (int64_t)(d * MUL);
}

class SBOStringData
{
public:
	SBOStringData(const MONEY &m) {
		m_str = new wchar_t[50];
#ifdef _WINDOWS
		m_len = swprintf(m_str, L"%lf", m.ToDouble());
#else
		m_len = swprintf(m_str, 50, L"%lf", m.ToDouble());
#endif
	}
	~SBOStringData() {
		delete m_str;
	}
private:
	wchar_t *m_str;
	int m_len;
	friend class SBOString;
};

class SBOString
{
public:
	SBOString(const MONEY &m) {
		m_strData = new SBOStringData(m);
	}
	~SBOString() {
		delete m_strData;
	}
	const wchar_t *GetBuffer() const {
		return m_strData->m_str;
	}
private:
	SBOStringData *m_strData;
};

void ShowStr(const SBOString &str)
{
	printf("%s\n", str.GetBuffer());
}

int main()
{
	MONEY m(3.1415);
	int i;
	for (i=0; i<5; ++i) {
		SBOString s(m);
		const wchar_t *str = s.GetBuffer();
		double d = m.ToDouble();
		AddMoney(&m, 1.14);
		printf("%.2lf, %ls\n", d, str);
		ShowStr(s);
	}
	return 0;
}

