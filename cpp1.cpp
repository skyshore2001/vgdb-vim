#include <stdio.h>
#include <stdint.h>
#include <wchar.h>
#include <stdexcept>

#define MUL 1000000.0

class MoneyOverflowException: public std::runtime_error
{
public:
	MoneyOverflowException(): std::runtime_error("Money Overflow") {}
};

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

	MONEY &Add(double d)
	{
		if (ToDouble() + d > 10000.0)
		{
			throw MoneyOverflowException();
		}
		m_data[0] += (int64_t)(d * MUL);
	}

private:
	int64_t m_data[2];
};

class SBOStringData
{
public:
	SBOStringData(const MONEY &m) {
		m_str = new wchar_t[50];
#ifdef _WINDOWS
		m_len = swprintf(m_str, L"%.2lf", m.ToDouble());
#else
		m_len = swprintf(m_str, 50, L"%.2lf", m.ToDouble());
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

int main()
{
	MONEY m(8888.123);
	try {
		for (int i=0; i<10; ++i) {
			m.Add(234.512);
			SBOString s(m);
			printf("i=%d, %lf, %ls\n", i, m.ToDouble(), s.GetBuffer());
		}
	}
	catch (std::exception &e) {
		printf("Exception: %s\n", e.what());
	}
	return 0;
}

